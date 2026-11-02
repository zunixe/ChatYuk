-- ══════════════════════════════════════════════════════════════════════
-- Fase 1 — Ekonomi koin berbasis gender (keputusan produk 2026-10-31)
--
-- Model akhir:
--   • MALE   : bayar koin untuk call/video/gift/unlock foto ke female.
--              Dapat bonus koin gratis (bucket `bonus`, diskon 3× saat belanja).
--   • FEMALE : chat GRATIS ke siapa saja, call/video GRATIS ke siapa saja
--              (dengan batas menit/hari), TIDAK dapat bonus koin.
--              Penghasilan murni dari aktivitas male → bucket `earned`.
--   • PLATFORM : ambil 70% call, 30% gift, 40% unlock foto.
--              Female withdraw hanya dari bucket `earned` (rate Rp 7/koin).
--
-- Chat teks jadi GRATIS untuk semua gender. Foto (3) & view-once (5)
-- tetap berbayar — ini pendorong top-up male.
-- ══════════════════════════════════════════════════════════════════════

-- ── 0. Setting baru: batas menit call gratis female → male per hari ──
ALTER TABLE public.app_settings
    ADD COLUMN IF NOT EXISTS female_free_call_min_per_day int NOT NULL DEFAULT 30;

-- Default: 30 menit/hari. Ubah lewat admin panel kalau perlu.
UPDATE public.app_settings
    SET female_free_call_min_per_day = 30
    WHERE id = 'global' AND female_free_call_min_per_day IS NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 1. deduct_chat_point — chat TEKS gratis (foto & view-once tetap bayar)
--    FROZEN → header wajib.
-- ══════════════════════════════════════════════════════════════════════
-- menyentuh: deduct_chat_point
CREATE OR REPLACE FUNCTION public.deduct_chat_point(msg_type text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare points_on boolean; cost int; remaining int; c_text int; c_img int; c_vo int;
begin
  select points_enabled, cost_chat_text, cost_chat_image, cost_view_once
    into points_on, c_text, c_img, c_vo from app_settings where id = 'global';
  if points_on is false then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;
  -- 2026-10-31: chat TEKS gratis untuk semua gender. Hanya foto & view-once
  -- yang berbayar (pendorong top-up male + income female dari unlock foto).
  cost := case msg_type
    when 'image' then c_img
    when 'view_once' then c_vo
    when 'view_once_expired' then 0
    else 0 end;
  if cost = 0 then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;
  remaining := public.ledger_spend(auth.uid(), 'spend_chat', cost, msg_type);
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));
  return remaining;
end; $function$;

-- ══════════════════════════════════════════════════════════════════════
-- 2. call_billing_tick — caller FEMALE = gratis (batas menit/hari)
--    Bukan FROZEN.
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.call_billing_tick(p_call_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  c record;
  feat text; unit_cost int; cut_pct int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  afford int; charge_n int;
  remaining int;
  points_on boolean;
  v_caller_gender text;
  v_callee_gender text;
  v_free_limit int;
  v_free_used numeric;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Master toggle koin (admin "Sistem poin") PALING ATAS — jalur OFF
  -- tak menyentuh config/billing, call gratis total.
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    return jsonb_build_object(
      'ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  -- Gerbang fitur publish — jalur OFF tak menyentuh config/billing.
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  -- ── 2026-10-31: caller FEMALE = GRATIS (batas menit/hari) ──
  select gender into v_caller_gender from public.profiles where id = me;
  if v_caller_gender = 'female' then
    select coalesce(female_free_call_min_per_day, 30) into v_free_limit
      from app_settings where id = 'global';
    -- Menit gratis yang sudah terpakai hari ini (call ke male yang sudah
    -- dijawab). Dihitung server-side dari `calls` — anti-tamper client.
    select coalesce(sum(ceil(extract(epoch from
             (coalesce(cc.ended_at, now()) - cc.answered_at)) / 60)), 0)
      into v_free_used
      from public.calls cc
      join public.profiles pp on pp.id = cc.callee_id
     where cc.caller_id = me
       and cc.callee_id <> me
       and pp.gender = 'male'
       and cc.answered_at is not null
       and cc.answered_at >= current_date;
    if v_free_used >= v_free_limit then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
        'remaining', public.yukcoin_total(me),
        'reason', 'free_limit',
        'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
    end if;
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me),
      'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
  end if;

  -- Random video call: GRATIS dulu (keputusan produk 2026-10-30).
  if c.kind = 'random' then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  feat := case c.call_type when 'audio' then 'call_audio' else 'call_video' end;
  select case c.call_type
           when 'audio' then call_audio_cost_per_min
           else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);
  cut_pct := coalesce((select call_cut_pct from app_settings where id='global'), 70);
  -- Belum dijawab → belum ada tagihan.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;
  -- Detik berjalan SERVER-SIDE dari answered_at (anti-tamper client).
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);
  -- Menit berbayar = ceil(elapsed / 60).
  billable_minutes := (elapsed_sec + 59) / 60;
  -- Sudah ditagih berapa menit untuk call ini (idempoten).
  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = me and feature = feat and ref_id = p_call_id::text;
  to_bill := greatest(0, billable_minutes - already_billed);
  remaining := public.yukcoin_total(me);
  if to_bill > 0 then
    if remaining < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient');
    end if;
    -- Tagih sebanyak yang sanggup (afford-guard → saldo tak pernah minus).
    afford := remaining / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public.charge_metered(me, feat, p_call_id::text, charge_n, c.callee_id);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select me, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g, 'call_type', c.call_type)
        from generate_series(1, charge_n) g;
      already_billed := already_billed + charge_n;
      remaining := public.yukcoin_total(me);
    end if;
    if charge_n < to_bill or remaining < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient');
    end if;
  end if;
  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
    'remaining', remaining);
end; $function$;

-- ══════════════════════════════════════════════════════════════════════
-- 3. charge_metered — callee MALE tidak dapat income (platform ambil 100%)
--    Bukan FROZEN.
-- ══════════════════════════════════════════════════════════════════════
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
  if auth.uid() is not null and p_caller is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh menagih user lain'
      using errcode = '42501';
  end if;
  if p_caller is null then raise exception 'Not authenticated'; end if;
  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;
  select metered_pricing -> p_feature into cfg
    from app_settings where id = 'global';
  if cfg is null then
    raise exception 'Unknown metered feature: %', p_feature;
  end if;
  unit_cost := coalesce((cfg->>'unit_cost')::int, 0);
  cut_pct   := coalesce((cfg->>'cut_pct')::int, 0);
  total := unit_cost * p_units;
  if total <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;
  balance := public.yukcoin_total(p_caller);
  if balance < total then
    raise exception 'YukCoin tidak cukup';
  end if;
  -- Potong dari saldo penelepon (semua bucket boleh dipakai).
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

-- ══════════════════════════════════════════════════════════════════════
-- 4. credit_welcome_bonus — MALE only (female tidak dapat koin gratis)
--    Bukan FROZEN.
-- ══════════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════════
-- 5. claim_mission_reward — reward misi → bucket `earned` (withdrawable)
--    Bukan FROZEN.
-- ══════════════════════════════════════════════════════════════════════
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

-- Grants
REVOKE EXECUTE ON FUNCTION public.deduct_chat_point(text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.call_billing_tick(uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.credit_welcome_bonus(uuid, text, text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.deduct_chat_point(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.call_billing_tick(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.credit_welcome_bonus(uuid, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;
