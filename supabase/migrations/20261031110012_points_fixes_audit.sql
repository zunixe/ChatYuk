-- ══════════════════════════════════════════════════════════════════════
-- Audit poin end-to-end (2026-10-31) — perbaikan inkonsistensi.
--
-- 1. charge_metered: harga call baca KOLOM (call_*_cost_per_min,
--    call_cut_pct) yang diedit admin — bukan metered_pricing JSONB yang
--    basi sejak 1 Okt. JSONB tetap fallback untuk fitur non-call.
-- 2. Sync metered_pricing JSONB dari kolom saat ini (satu kali).
-- 3. Auth guard di 4 RPC misi (p_user_id harus = auth.uid() bila dipanggil
--    user terautentikasi; service_role tetap bebas).
-- 4. admin_mass_bonus: skip female (female tidak boleh punya bonus).
-- 5. get_earnings_summary: whitelist income selaras tipe ledger aktual
--    (+coin_received, subscribe_income, photo_income).
-- 6. spend_yukcoin: female gratis untuk match_search (parity client) +
--    fee match_search tercatat di platform_revenue (hangus = revenue).
-- 7. check_user_total_coins / get_user_missions: "total koin" = KUMULATIF
--    kredit seumur hidup (bukan saldo) — unlock misi tidak turun saat
--    user membelanjakan koin.
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. charge_metered — sumber harga = kolom untuk call ─────────────────
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

-- ── 2. Sync metered_pricing JSONB dari kolom (satu kali) ────────────────
update public.app_settings
   set metered_pricing = jsonb_set(
         jsonb_set(metered_pricing, '{call_audio}',
           jsonb_build_object('unit_cost', call_audio_cost_per_min,
                              'cut_pct', call_cut_pct, 'model', 'per_min')),
         '{call_video}',
           jsonb_build_object('unit_cost', call_video_cost_per_min,
                              'cut_pct', call_cut_pct, 'model', 'per_min'))
 where id = 'global';

-- ── 3. Auth guard di RPC misi ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_mission_progress(
    p_user_id uuid,
    p_mission_key text,
    p_increment int DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mission record;
    v_period date;
    v_progress int;
    v_completed boolean;
BEGIN
    -- GUARD (audit 2026-10-31): user hanya boleh mengubah misi SENDIRI.
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    SELECT * INTO v_mission
    FROM public.missions
    WHERE mission_key = p_mission_key;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    -- Misi harian reset tiap hari; misi utama = seumur hidup (period_date NULL)
    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

    INSERT INTO public.user_missions
        (user_id, mission_id, progress, is_completed, completed_at, period_date)
    VALUES (
        p_user_id,
        v_mission.id,
        LEAST(p_increment, v_mission.target_value),
        p_increment >= v_mission.target_value,
        CASE WHEN p_increment >= v_mission.target_value THEN now() END,
        v_period
    )
    ON CONFLICT (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date)) DO UPDATE SET
        progress = LEAST(user_missions.progress + p_increment, v_mission.target_value),
        is_completed = (user_missions.progress + p_increment >= v_mission.target_value),
        completed_at = CASE
            WHEN user_missions.progress + p_increment >= v_mission.target_value
                 AND NOT user_missions.is_completed
            THEN now()
            ELSE user_missions.completed_at
        END
    RETURNING progress, is_completed INTO v_progress, v_completed;

    RETURN jsonb_build_object(
        'progress', v_progress,
        'target', v_mission.target_value,
        'completed', v_completed,
        'reward_coins', v_mission.reward_coins
    );
END;
$$;

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

CREATE OR REPLACE FUNCTION public.get_user_missions(
    p_user_id uuid,
    p_period_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result jsonb;
    v_period date;
    v_total bigint;
BEGIN
    -- GUARD (audit 2026-10-31): user hanya boleh membaca misi SENDIRI.
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    v_period := COALESCE(p_period_date, CURRENT_DATE);

    -- Total koin KUMULATIF seumur hidup = jumlah semua kredit (bukan saldo
    -- bersih) — unlock misi harian @1200 tidak turun saat user belanja.
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM public.coin_ledger
    WHERE user_id = p_user_id AND amount > 0;

    WITH main_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order,
               COALESCE(um.progress, 0) AS progress,
               COALESCE(um.is_completed, false) AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date IS NULL
        WHERE NOT m.is_daily
    ),
    daily_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order, m.unlock_condition, m.schedule_start, m.schedule_end,
               COALESCE(um.progress, 0) AS progress,
               COALESCE(um.is_completed, false) AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at,
               (v_total >= 1200) AS unlocked_by_total
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date = v_period
        WHERE m.is_daily
    )
    SELECT jsonb_build_object(
        'main', (SELECT jsonb_agg(row_to_json(m) ORDER BY m.display_order) FROM main_missions m),
        'daily', (SELECT jsonb_agg(row_to_json(dm) ORDER BY dm.display_order) FROM daily_missions dm),
        'total_coins', v_total
    ) INTO result;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_user_total_coins(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    total_coins int;
BEGIN
    -- GUARD (audit 2026-10-31): hanya boleh membaca milik sendiri.
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    -- Kumulatif kredit seumur hidup (selaras get_user_missions).
    SELECT COALESCE(SUM(amount), 0) INTO total_coins
    FROM public.coin_ledger
    WHERE user_id = p_user_id AND amount > 0;

    RETURN jsonb_build_object('total_coins', total_coins);
END;
$$;

-- ── 4. admin_mass_bonus — female tidak boleh punya bonus ────────────────
CREATE OR REPLACE FUNCTION public.admin_mass_bonus(bonus integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare affected int := 0; u uuid;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  -- Audit 2026-10-31: skip female — bonus hanya untuk male (female = earned).
  for u in select id from profiles where is_registered = true
           and coalesce(gender, '') <> 'female' loop
    perform public.ledger_credit(u, 'bonus', 'admin_mass_bonus', bonus);
    affected := affected + 1;
  end loop;
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_mass_bonus', bonus, jsonb_build_object('affected_users', affected));
  return jsonb_build_object('affected', affected, 'bonus', bonus);
end; $function$;

-- ── 5. get_earnings_summary — whitelist selaras tipe ledger aktual ──────
CREATE OR REPLACE FUNCTION public.get_earnings_summary(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result jsonb;
    v_total bigint;
    v_weekly bigint;
    v_today bigint;
    v_gift bigint;
    v_mission bigint;
    v_bonus bigint;
    v_call bigint;
    v_other bigint;
    v_withdrawable bigint;
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
BEGIN
    -- Audit 2026-10-31: whitelist diselaraskan dengan type yang benar-benar
    -- ditulis fungsi ekonomi. Versi lama melewatkan coin_received (kirim
    -- koin antar user), subscribe_income, dan photo_income (unlock_photo
    -- menulis 'photo_income', BUKAN 'photo_unlock_income').
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= date_trunc('week', now())), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= current_date), 0),
        COALESCE(SUM(amount) FILTER (WHERE type IN ('gift_recv','coin_received')), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'mission_reward'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type IN ('call_audio_income','call_video_income',
                           'private_call_income','match_call_income')), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type NOT IN ('gift_recv','coin_received','mission_reward',
                               'call_audio_income','call_video_income',
                               'private_call_income','match_call_income')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission, v_call, v_other
    FROM public.coin_ledger
    WHERE user_id = p_user_id
      AND amount > 0
      AND type IN (
            'gift_recv','coin_received',
            'mission_reward',
            'call_audio_income','call_video_income',
            'private_call_income','match_call_income',
            'photo_income','photo_unlock_income',
            'subscribe_income'
      )
      AND coalesce(ref_id, '') NOT IN ('t','test-income')
      AND coalesce(ref_id, '') NOT LIKE 'cleanup\_%'
      AND coalesce(ref_id, '') NOT LIKE 'female_bonus_reset\_%';

    -- ── Saldo yang bisa ditarik = saldo bersih semua bucket ──
    SELECT COALESCE(SUM(amount), 0) INTO v_withdrawable
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

    -- ── Statistik panggilan ──
    SELECT
        COUNT(*) FILTER (WHERE call_type = 'video'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE call_type = 'video' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint,
        COUNT(*) FILTER (WHERE kind = 'random'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE kind = 'random' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint
    INTO v_video_calls, v_video_seconds, v_match_calls, v_match_seconds
    FROM public.calls
    WHERE (caller_id = p_user_id OR callee_id = p_user_id)
      AND status = 'ended';

    SELECT COUNT(*), COUNT(*) FILTER (WHERE answered_at IS NOT NULL)
    INTO v_private_total, v_private_answered
    FROM public.calls
    WHERE callee_id = p_user_id
      AND coalesce(kind, '') <> 'random'
      AND status = 'ended';

    result := jsonb_build_object(
        'total_earnings', v_total,
        'weekly_earnings', v_weekly,
        'today_earnings', v_today,
        'withdrawable', v_withdrawable,
        'breakdown', jsonb_build_object(
            'private_call', v_call,
            'match_call', 0,
            'message', 0,
            'gift', v_gift,
            'mission', v_mission,
            'bonus', 0,
            'other', v_other
        ),
        'stats', jsonb_build_object(
            'video_call_count', v_video_calls,
            'video_call_seconds', v_video_seconds,
            'match_call_count', v_match_calls,
            'match_call_seconds', v_match_seconds,
            'avg_match_seconds', CASE
                WHEN v_match_calls > 0 THEN (v_match_seconds / v_match_calls)::bigint
                ELSE 0 END,
            'private_call_total', v_private_total,
            'private_call_answered', v_private_answered,
            'private_answer_rate', CASE
                WHEN v_private_total > 0
                THEN round((v_private_answered::numeric / v_private_total) * 100)
                ELSE 0 END
        )
    );

    RETURN result;
END;
$$;

-- ── 6. spend_yukcoin — female gratis match_search + revenue fee ─────────
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

-- ── 7. admin_update_point_settings — kembalikan yukcoin_v2_enabled ──────
-- Regresi: versi 20261003000200 menangani key ini, tapi rewrite 110004
-- menghilangkannya → toggle "YukCoin v2" di panel admin jadi no-op.
-- Kolom masih dipakai sebagai kill-switch fitur v2 (undo/edit/ghost/slot).
CREATE OR REPLACE FUNCTION public.admin_update_point_settings(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    -- Foto berbayar
    photo_upload_reward    = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once      = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm      = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct = coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    -- Pengali harga tier bonus (koin gratis = 1/multiplier dari koin beli)
    bonus_price_multiplier = coalesce((p->>'bonus_price_multiplier')::int, bonus_price_multiplier),
    -- Tarif call
    call_audio_cost_per_min = coalesce((p->>'call_audio_cost_per_min')::int, call_audio_cost_per_min),
    call_video_cost_per_min = coalesce((p->>'call_video_cost_per_min')::int, call_video_cost_per_min),
    call_cut_pct            = coalesce((p->>'call_cut_pct')::int, call_cut_pct),
    -- Fitur berbayar lain
    filter_gender_cost      = coalesce((p->>'filter_gender_cost')::int, filter_gender_cost),
    nearby_cost             = coalesce((p->>'nearby_cost')::int, nearby_cost),
    -- Room berbayar
    room_create_paid        = coalesce((p->>'room_create_paid')::int, room_create_paid),
    room_create_pw_paid     = coalesce((p->>'room_create_pw_paid')::int, room_create_pw_paid),
    room_join_paid          = coalesce((p->>'room_join_paid')::int, room_join_paid),
    room_extend_paid        = coalesce((p->>'room_extend_paid')::int, room_extend_paid),
    -- Gift & subscribe
    subscribe_cut_pct       = coalesce((p->>'subscribe_cut_pct')::int, subscribe_cut_pct),
    subscription_duration_days = coalesce((p->>'subscription_duration_days')::int, subscription_duration_days),
    gift_cut_pct            = coalesce((p->>'gift_cut_pct')::int, gift_cut_pct),
    -- Biaya chat
    cost_chat_text          = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image         = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once          = coalesce((p->>'cost_view_once')::int, cost_view_once),
    -- Share / reengage
    share_url               = coalesce(p->>'share_url', share_url),
    reengage_enabled        = coalesce((p->>'reengage_enabled')::boolean, reengage_enabled),
    -- Kill-switch fitur YukCoin v2 (undo/edit/ghost/slot foto — kini gratis).
    yukcoin_v2_enabled      = coalesce((p->>'yukcoin_v2_enabled')::boolean, yukcoin_v2_enabled),
    -- Welcome bonus user baru (anti-farming per install/IP)
    welcome_anon_coins      = coalesce((p->>'welcome_anon_coins')::int, welcome_anon_coins),
    welcome_register_coins  = coalesce((p->>'welcome_register_coins')::int, welcome_register_coins),
    welcome_max_claims_per_ip_day = coalesce((p->>'welcome_max_claims_per_ip_day')::int, welcome_max_claims_per_ip_day),
    -- ── Withdraw (tarik saldo `earned` ke DANA) ──
    withdraw_rate_idr       = coalesce((p->>'withdraw_rate_idr')::int, withdraw_rate_idr),
    withdraw_min_coins      = coalesce((p->>'withdraw_min_coins')::int, withdraw_min_coins),
    withdraw_fee_pct        = coalesce((p->>'withdraw_fee_pct')::int, withdraw_fee_pct),
    withdraw_fee_min_idr    = coalesce((p->>'withdraw_fee_min_idr')::int, withdraw_fee_min_idr),
    withdraw_max_per_day    = coalesce((p->>'withdraw_max_per_day')::int, withdraw_max_per_day),
    withdraw_min_interval_hours = coalesce((p->>'withdraw_min_interval_hours')::int, withdraw_min_interval_hours),
    withdraw_min_account_age_hours = coalesce((p->>'withdraw_min_account_age_hours')::int, withdraw_min_account_age_hours),
    -- ── Batas call gratis female → male (menit / hari) ──
    female_free_call_min_per_day = coalesce((p->>'female_free_call_min_per_day')::int, female_free_call_min_per_day),
    -- ── Anti-fraud: maks transaksi kirim koin/gift per jam ──
    coin_tx_max_per_hour    = coalesce((p->>'coin_tx_max_per_hour')::int, coin_tx_max_per_hour),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $function$;

-- ── Grants (CREATE OR REPLACE mewarisi, tapi pastikan) ──────────────────
REVOKE EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_missions(uuid, date) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.check_user_total_coins(uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.admin_mass_bonus(int) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_point_settings(jsonb) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_missions(uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_user_total_coins(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_mass_bonus(int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_point_settings(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) TO authenticated, service_role;
