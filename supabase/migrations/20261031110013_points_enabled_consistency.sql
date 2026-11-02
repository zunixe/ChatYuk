-- ══════════════════════════════════════════════════════════════════════
-- Konsistensi points_enabled (kill-switch ekonomi) — audit Fase 16.
--
-- Semantik yang sudah settle di fungsi lain (dipertahankan):
--   • Free-pass : aksi jalan tanpa menagih (deduct_chat_point, unlock_photo,
--                 gate_feature, call_billing_tick).
--   • Block     : transfer/nilai ke user lain (send_coins, send_gift,
--                 subscribe_creator) → raise 'Points system disabled'.
--   • No-credit : earn → no-op graceful (new_chat_bonus, daily_login, ...).
--
-- Gap yang ditutup di sini:
--   • spend_yukcoin      : tak cek flag → fee match_search tetap menagih saat
--                          poin OFF → free-pass semua feature.
--   • charge_metered     : tak cek flag (bisa dipanggil langsung) → free-pass.
--   • request_withdraw   : tak cek flag → pengajuan tetap diterima saat OFF →
--                          {ok:false, error:'POINTS_DISABLED'} (pola yang sama
--                          dengan FEMALE_ONLY di fungsi ini).
--   • claim_mission_reward: tetap kredit `earned` saat ekonomi mati →
--                          {error:'POINTS_DISABLED'}.
--   • credit_welcome_bonus: welcome coin tetap masuk saat OFF →
--                          granted:false reason 'points_disabled' (graceful;
--                          edge fn sudah menangani granted:false).
-- Biarkan: update_mission_progress (progress ≠ ekonomi), undo/edit/buy_*_v2
-- (punya kill-switch sendiri: yukcoin_v2_enabled), semua fungsi read & admin.
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. spend_yukcoin — free-pass bila points_enabled=false ──────────
CREATE OR REPLACE FUNCTION public.spend_yukcoin(p_user uuid, p_feature text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e int; b int; need int; take int; tier text;
begin
  if auth.uid() is not null and p_user is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh mendebit saldo user lain'
      using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  -- 2026-10-31 (audit): kill-switch ekonomi. points_enabled=false → semua
  -- spend jadi FREE (pola unlock_photo/deduct_chat_point/call_billing_tick).
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;
  -- 2026-10-31: hanya GIFT + biaya pencarian MATCH yang memotong poin.
  -- undo, edit, slot foto, mode hantu, filter, nearby → GRATIS.
  if p_feature not in ('gift','gift_sent','match_search') then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  -- Audit: female tidak pernah keluar koin (parity dengan client
  -- _chargeMatchFee yang skip female). Tanpa ini, pemanggil API langsung
  -- tetap bisa menagih female.
  if p_feature = 'match_search'
     and (select gender from public.profiles where id = p_user) = 'female' then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = p_user;

  if (e + b) < p_amount then
    raise exception 'YukCoin tidak cukup';
  end if;

  need := p_amount;
  take := least(e, need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (p_user, 'earned', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
    need := need - take;
  end if;
  if need > 0 then
    take := least(b, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
  end if;

  tier := case when e >= p_amount then 'earned' else 'mixed' end;

  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (p_user, p_feature, p_amount, p_ref, coalesce(p_meta, '{}'::jsonb));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, p_feature, -p_amount,
            jsonb_build_object('feature', p_feature, 'ref', p_ref, 'tier', tier));

  -- Audit: fee pencarian match hangus (tidak ada penerima) → catat sebagai
  -- revenue platform supaya laporan ekonomi utuh.
  if p_feature = 'match_search' then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('match_search', p_amount, p_user, null, p_ref,
              jsonb_build_object('kind', 'search_fee'));
  end if;

  return jsonb_build_object('tier', tier, 'charged', p_amount,
    'remaining', public.yukcoin_total(p_user));
end;
$function$;

-- ── 2. charge_metered — free-pass bila points_enabled=false ─────────
CREATE OR REPLACE FUNCTION public.charge_metered(p_caller uuid, p_feature text, p_ref text, p_units integer DEFAULT 1, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cfg jsonb; unit_cost int; cut_pct int;
  total int; cut int; net int; remaining int; balance int;
  v_recipient_gender text;
begin
  -- GUARD KEAMANAN (2026-10-22): user hanya boleh menagih DIRINYA sendiri.
  -- call_billing_tick sudah mengisi p_caller := auth.uid() → tetap jalan.
  if auth.uid() is not null and p_caller is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh menagih user lain'
      using errcode = '42501';
  end if;
  if p_caller is null then raise exception 'Not authenticated'; end if;
  -- 2026-10-31 (audit): kill-switch ekonomi — free-pass seperti
  -- call_billing_tick (yang sudah mengecek flag lebih dulu).
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  -- 2026-10-31 (audit): untuk call, harga & cut = KOLOM app_settings yang
  -- diedit admin lewat admin_update_point_settings. metered_pricing JSONB
  -- basi (seed 1 Okt, tak pernah diupdate) → dua sumber kebenaran bikin
  -- tampilan per_menit ≠ debit aktual. JSONB tetap fallback fitur lain.
  if p_feature = 'call_audio' then
    select call_audio_cost_per_min, call_cut_pct into unit_cost, cut_pct
      from app_settings where id = 'global';
  elsif p_feature = 'call_video' then
    select call_video_cost_per_min, call_cut_pct into unit_cost, cut_pct
      from app_settings where id = 'global';
  else
    select metered_pricing -> p_feature into cfg
      from app_settings where id = 'global';
    if cfg is null then
      raise exception 'Unknown metered feature: %', p_feature;
    end if;
    unit_cost := (cfg->>'unit_cost')::int;
    cut_pct   := (cfg->>'cut_pct')::int;
  end if;
  unit_cost := coalesce(unit_cost, 0);
  cut_pct   := coalesce(cut_pct, 0);

  total := unit_cost * p_units;
  if total <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  balance := public.yukcoin_total(p_caller);
  if balance < total then
    raise exception 'YukCoin tidak cukup';
  end if;

  -- Potong dari saldo penelepon (semua bucket boleh dipakai — ekosistem
  -- coin tertutup: coin dari topup & dari income call sama-sama bisa dipakai).
  remaining := public.ledger_spend(p_caller, p_feature, total, p_ref);

  -- Split ke penerima (mis. pemilik call). Platform ambil cut_pct.
  cut := (total * cut_pct) / 100;
  net := total - cut;
  -- 2026-10-31: HANYA FEMALE yang dapat income. Male tidak pernah
  -- memperoleh koin dari aktivitas user lain (platform ambil 100%).
  if p_recipient is not null and p_recipient <> p_caller and net > 0 then
    select gender into v_recipient_gender from public.profiles where id = p_recipient;
    if v_recipient_gender = 'female' then
      perform public.ledger_credit(p_recipient, 'earned', p_feature || '_income',
        net, p_ref, jsonb_build_object('from', p_caller, 'feature', p_feature,
        'gross', total, 'cut', cut));
      insert into public.point_events (user_id, event, amount, metadata)
        values (p_recipient, p_feature || '_income', net,
                jsonb_build_object('from', p_caller, 'ref', p_ref));
    end if;
  end if;

  -- Catat revenue platform (cut).
  if cut > 0 then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (p_feature, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, p_feature, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $function$;

-- ── 3. request_withdraw — block pengajuan saat points OFF ───────────
CREATE OR REPLACE FUNCTION public.request_withdraw(
    p_coins int,
    p_dana_number text DEFAULT NULL,
    p_dana_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_gender text;
    v_total int;
    v_min_coins int;
    v_rate int;
    v_fee_pct int;
    v_fee_min int;
    v_max_day int;
    v_min_interval int;
    v_min_age int;
    v_today_count int;
    v_last_req timestamptz;
    v_created_at timestamptz;
    v_gross int;
    v_fee int;
    v_net int;
    v_num text;
    v_name text;
    v_acc record;
    v_req_id uuid;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- 2026-10-31 (audit): kill-switch ekonomi — pengajuan withdraw diblok
    -- saat poin OFF (block, konsisten dgn send_gift/send_coins/subscribe).
    IF (SELECT points_enabled FROM app_settings WHERE id = 'global') IS FALSE THEN
        RETURN jsonb_build_object('ok', false, 'error', 'POINTS_DISABLED');
    END IF;


    SELECT gender INTO v_gender FROM public.profiles WHERE id = v_uid;
    IF v_gender IS DISTINCT FROM 'female' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'FEMALE_ONLY');
    END IF;

    SELECT coalesce(withdraw_min_coins, 1500),
           coalesce(withdraw_rate_idr, 7),
           coalesce(withdraw_fee_pct, 5),
           coalesce(withdraw_fee_min_idr, 1000),
           coalesce(withdraw_max_per_day, 3),
           coalesce(withdraw_min_interval_hours, 1),
           coalesce(withdraw_min_account_age_hours, 72)
      INTO v_min_coins, v_rate, v_fee_pct, v_fee_min,
           v_max_day, v_min_interval, v_min_age
      FROM public.app_settings WHERE id = 'global';

    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

    -- 2026-10-31: female boleh menarik SEMUA koinnya (total saldo),
    -- bukan hanya bucket `earned`. Jalur masuk koin gratis ke female
    -- sudah ditutup (send_gift & unlock_photo wajib koin beli).
    SELECT coalesce(sum(amount), 0) INTO v_total
      FROM public.coin_ledger WHERE user_id = v_uid;

    IF v_total < p_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INSUFFICIENT_BALANCE',
            'balance', v_total);
    END IF;

    SELECT created_at INTO v_created_at FROM public.profiles WHERE id = v_uid;
    IF v_created_at IS NOT NULL
       AND v_created_at > now() - make_interval(hours => v_min_age) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ACCOUNT_TOO_NEW',
            'min_age_hours', v_min_age);
    END IF;

    SELECT count(*) INTO v_today_count
      FROM public.withdrawal_requests
     WHERE user_id = v_uid AND created_at >= current_date;
    IF v_today_count >= v_max_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_LIMIT',
            'max_per_day', v_max_day);
    END IF;

    SELECT max(created_at) INTO v_last_req
      FROM public.withdrawal_requests WHERE user_id = v_uid;
    IF v_last_req IS NOT NULL
       AND v_last_req > now() - make_interval(hours => v_min_interval) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'TOO_SOON',
            'min_interval_hours', v_min_interval);
    END IF;

    -- Akun DANA: pakai yang dikirim, atau yang tersimpan.
    IF p_dana_number IS NOT NULL AND p_dana_name IS NOT NULL THEN
        v_num := regexp_replace(p_dana_number, '[^0-9]', '', 'g');
        IF v_num !~ '^(08|62)[0-9]{8,13}$' THEN
            RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NUMBER');
        END IF;
        IF v_num LIKE '62%' THEN v_num := '0' || substring(v_num from 3); END IF;
        v_name := nullif(trim(p_dana_name), '');
        IF v_name IS NULL OR length(v_name) < 3 THEN
            RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NAME');
        END IF;
        INSERT INTO public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
        VALUES (v_uid, v_num, v_name, now())
        ON CONFLICT (user_id) DO UPDATE SET
            dana_number = excluded.dana_number,
            dana_name = excluded.dana_name,
            updated_at = now();
    ELSE
        SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'error', 'NO_ACCOUNT');
        END IF;
        v_num := v_acc.dana_number;
        v_name := v_acc.dana_name;
    END IF;

    v_gross := p_coins * v_rate;
    v_fee := greatest((v_gross * v_fee_pct) / 100, v_fee_min);
    IF v_fee > v_gross THEN v_fee := v_gross; END IF;
    v_net := v_gross - v_fee;

    INSERT INTO public.withdrawal_requests
        (user_id, coin_amount, payout_idr, gross_idr, fee_idr, rate,
         status, pay_method, pay_account, pay_holder)
    VALUES
        (v_uid, p_coins, v_net, v_gross, v_fee, v_rate,
         'pending', 'ewallet', v_num, v_name)
    RETURNING id INTO v_req_id;

    RETURN jsonb_build_object('ok', true, 'id', v_req_id,
        'coins', p_coins, 'rate', v_rate,
        'gross_idr', v_gross, 'fee_idr', v_fee, 'net_idr', v_net,
        'dana_number', v_num, 'dana_name', v_name,
        'status', 'pending');
END;
$$;

-- ── 4. claim_mission_reward — block kredit saat points OFF ──────────
CREATE OR REPLACE FUNCTION public.claim_mission_reward(
    p_user_id uuid,
    p_mission_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mission record;
    v_user_mission record;
    v_period date;
    v_new_points int;
BEGIN
    -- GUARD (audit 2026-10-31): user hanya boleh klaim misi SENDIRI.
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    -- 2026-10-31 (audit): ekonomi OFF → reward misi (kredit `earned`) ikut
    -- diblok. Progress (update_mission_progress) tetap jalan — bukan ekonomi.
    IF (SELECT points_enabled FROM app_settings WHERE id = 'global') IS FALSE THEN
        RETURN jsonb_build_object('error', 'POINTS_DISABLED');
    END IF;

    SELECT * INTO v_mission
    FROM public.missions
    WHERE mission_key = p_mission_key;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

    SELECT * INTO v_user_mission
    FROM public.user_missions
    WHERE user_id = p_user_id
      AND mission_id = v_mission.id
      AND COALESCE(period_date, '1970-01-01'::date) = COALESCE(v_period, '1970-01-01'::date);

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_STARTED');
    END IF;

    IF NOT v_user_mission.is_completed THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
    END IF;

    IF v_user_mission.claimed THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;

    UPDATE public.user_missions
    SET claimed = true, claimed_at = now()
    WHERE id = v_user_mission.id;

    -- 2026-10-31: reward misi masuk bucket `earned` (bisa di-withdraw),
    -- karena misi khusus FEMALE dan female penghasilannya dari bucket ini.
    -- Trigger trg_coin_ledger_balance() OTOMATIS menambah profiles.points.
    INSERT INTO public.coin_ledger (user_id, bucket, type, amount, ref_id)
    VALUES (p_user_id, 'earned', 'mission_reward', v_mission.reward_coins, p_mission_key);

    SELECT points INTO v_new_points
    FROM public.profiles
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'coins', v_mission.reward_coins,
        'total_points', v_new_points
    );
END;
$$;

-- ── 5. credit_welcome_bonus — no-credit saat points OFF ─────────────
CREATE OR REPLACE FUNCTION public.credit_welcome_bonus(p_user uuid, p_install_id text, p_kind text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  coins int; max_ip int; ip_count int; tot int; existing int;
  v_gender text;
begin
  if p_user is null then raise exception 'Missing user'; end if;
  if p_kind not in ('anon','register') then
    raise exception 'Invalid kind: %', p_kind;
  end if;
  if p_install_id is null or length(trim(p_install_id)) < 6 then
    raise exception 'Invalid install_id';
  end if;
  -- 2026-10-31 (audit): ekonomi OFF → welcome coin tidak diberikan
  -- (no-credit graceful; edge fn welcome-bonus menangani granted:false).
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'points_disabled', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;
  -- 2026-10-31: bonus koin HANYA untuk MALE. Female penghasilannya dari
  -- aktivitas male (bucket `earned`), bukan koin gratis.
  select gender into v_gender from public.profiles where id = p_user;
  if v_gender = 'female' then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'female_no_bonus', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;
  select case p_kind
           when 'anon' then coalesce(welcome_anon_coins,100)
           else coalesce(welcome_register_coins,100) end,
         coalesce(welcome_max_claims_per_ip_day, 3)
    into coins, max_ip
    from app_settings where id = 'global';
  -- Lapis 1: install_id + kind sudah pernah klaim?
  select count(*) into existing from public.bonus_claims
    where install_id = p_install_id and kind = p_kind;
  if existing > 0 then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'already_claimed', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;
  -- Lapis 2: limit klaim per IP / 24 jam (bila IP tersedia).
  if p_ip is not null and length(trim(p_ip)) > 0 then
    select count(*) into ip_count from public.bonus_claims
      where ip = p_ip and kind = p_kind
        and created_at > now() - interval '24 hours';
    if ip_count >= max_ip then
      return jsonb_build_object('ok', true, 'granted', false,
        'reason', 'ip_limit', 'coins', 0,
        'total', public.yukcoin_total(p_user));
    end if;
  end if;
  -- Beri bonus (ke bucket 'bonus' — diskon 3× saat belanja).
  insert into public.bonus_claims(install_id, kind, user_id, ip)
    values (p_install_id, p_kind, p_user, nullif(trim(coalesce(p_ip,'')), ''))
    on conflict (install_id, kind) do nothing;
  if not found then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'race', 'coins', 0, 'total', public.yukcoin_total(p_user));
  end if;
  tot := public.ledger_credit(p_user, 'bonus', 'welcome_' || p_kind, coins,
           null, jsonb_build_object('install_id', p_install_id, 'ip', p_ip));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, 'welcome_' || p_kind, coins,
            jsonb_build_object('install_id', p_install_id));
  return jsonb_build_object('ok', true, 'granted', true, 'coins', coins,
    'total', tot);
end; $function$;

-- ── Grants (CREATE OR REPLACE mewarisi, tapi pastikan) ──────────────────
REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.request_withdraw(int, text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.credit_welcome_bonus(uuid, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_withdraw(int, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.credit_welcome_bonus(uuid, text, text, text) TO authenticated, service_role;
