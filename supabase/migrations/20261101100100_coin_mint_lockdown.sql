-- ============================================================
-- 20261101100100_coin_mint_lockdown.sql
-- KEAMANAN EKONOMI — tutup tiga jalur pencetakan koin gratis.
--
-- 1. credit_welcome_bonus: 20261031110013 memberi GRANT ke `authenticated`.
--    Badan fungsi tidak pernah memeriksa auth.uid(), dan batas per-IP
--    dilewati bila p_ip NULL. Siapa pun bisa memanggil berulang dengan
--    install_id acak → 100 koin gratis tiap panggilan.
--    → kembali `service_role` saja (edge fn `welcome-bonus` memakai
--      service_role, jadi alur normal tidak berubah).
--
-- 2. charge_metered: p_recipient adalah input bebas client dan tidak
--    divalidasi terhadap call. Memakai ledger_spend yang boleh memakai
--    bucket `bonus` → male bisa memindahkan koin gratis ke akun female
--    miliknya sendiri sebagai `earned` (withdrawable).
--    → `service_role` saja (pemanggil sah: call_billing_tick &
--      _spend_yukcoin_core, keduanya SECURITY DEFINER) + validasi
--      p_recipient harus callee dari call tersebut.
--
-- 3. Misi: update_mission_progress menerima p_increment tanpa batas, dan
--    user_missions punya policy FOR ALL USING(user_id=auth.uid()) sehingga
--    client bisa menulis is_completed=true langsung. Reward masuk `earned`
--    (withdrawable).
--    → clamp increment, pisahkan policy (SELECT saja untuk client),
--      cabut INSERT/UPDATE/DELETE tabel, dan claim atomik.
-- ============================================================

-- ── 1. credit_welcome_bonus — service_role saja + guard caller ─────────
CREATE OR REPLACE FUNCTION public.credit_welcome_bonus(p_user uuid, p_install_id text, p_kind text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  coins int; max_ip int; ip_count int; tot int; existing int;
  v_gender text;
  v_is_client boolean := coalesce(auth.role(), '') = 'authenticated';
begin
  if p_user is null then raise exception 'Missing user'; end if;
  -- GUARD (defense in depth; akses utama dijaga GRANT di §4): pemanggil
  -- CLIENT hanya boleh mengkredit dirinya sendiri. Edge function memakai
  -- service_role → auth.role() bukan 'authenticated' → lolos.
  if v_is_client and auth.uid() is not null and p_user <> auth.uid() then    raise exception 'Forbidden: tidak boleh mengkredit user lain'
      using errcode = '42501';
  end if;
  if p_kind not in ('anon','register') then
    raise exception 'Invalid kind: %', p_kind;
  end if;
  if p_install_id is null or length(trim(p_install_id)) < 6 then
    raise exception 'Invalid install_id';
  end if;
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'points_disabled', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;
  -- 2026-10-31: bonus koin HANYA untuk MALE.
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
  select count(*) into existing from public.bonus_claims
    where install_id = p_install_id and kind = p_kind;
  if existing > 0 then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'already_claimed', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;
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

-- ── 2. charge_metered — service_role saja + validasi recipient ─────────
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
  v_callee uuid;
begin
  -- Akses dijaga GRANT: EXECUTE dicabut dari authenticated (lihat §4).
  -- call_billing_tick memanggil sebagai definer (owner), jadi tetap jalan.
  if p_caller is null then raise exception 'Not authenticated'; end if;
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  -- GUARD: untuk call, penerima income WAJIB callee dari call tersebut.
  -- Tanpa ini male bisa menyalurkan koin ke akun female miliknya sendiri.
  if p_feature in ('call_audio','call_video') then
    select c.callee_id into v_callee
      from public.calls c
     where c.id::text = p_ref;
    if v_callee is not null and p_recipient is not null
       and p_recipient <> v_callee then
      raise exception 'Forbidden: penerima bukan callee call ini'
        using errcode = '42501';
    end if;
  end if;

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

  remaining := public.ledger_spend(p_caller, p_feature, total, p_ref);

  cut := (total * cut_pct) / 100;
  net := total - cut;
  -- HANYA FEMALE yang dapat income.
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

-- ── 3a. update_mission_progress — clamp increment ──────────────────────
-- Klien hanya boleh melaporkan sedikit kemajuan per panggilan (event nyata
-- = 1, tick online = ≤5 menit). P_increment di luar 1..120 diabaikan;
-- tanpa ini p_increment = 10^9 menyelesaikan misi apa pun.
CREATE OR REPLACE FUNCTION public.update_mission_progress(
    p_user_id uuid,
    p_mission_key text,
    p_increment int DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_mission record;
    v_period date;
    v_progress int;
    v_completed boolean;
    v_inc int;
BEGIN
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    -- Clamp 1..120: nilai di luar itu dianggap tidak sah.
    v_inc := coalesce(p_increment, 1);
    if v_inc < 1 then v_inc := 1; end if;
    if v_inc > 120 then v_inc := 120; end if;

    SELECT * INTO v_mission
    FROM public.missions
    WHERE mission_key = p_mission_key;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

    INSERT INTO public.user_missions
        (user_id, mission_id, progress, is_completed, completed_at, period_date)
    VALUES (
        p_user_id,
        v_mission.id,
        LEAST(v_inc, v_mission.target_value),
        v_inc >= v_mission.target_value,
        CASE WHEN v_inc >= v_mission.target_value THEN now() END,
        v_period
    )
    ON CONFLICT (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date)) DO UPDATE SET
        progress = LEAST(user_missions.progress + v_inc, v_mission.target_value),
        is_completed = (user_missions.progress + v_inc >= v_mission.target_value),
        completed_at = CASE
            WHEN user_missions.progress + v_inc >= v_mission.target_value
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

-- ── 3b. claim_mission_reward — claim atomik (anti dobel kredit) ────────
CREATE OR REPLACE FUNCTION public.claim_mission_reward(
    p_user_id uuid,
    p_mission_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_mission record;
    v_user_mission record;
    v_period date;
    v_new_points int;
    v_claimed_id bigint;
BEGIN
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

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
      AND COALESCE(period_date, '1970-01-01'::date) = COALESCE(v_period, '1970-01-01'::date)
      FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_STARTED');
    END IF;

    IF NOT v_user_mission.is_completed THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
    END IF;

    IF v_user_mission.claimed THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;

    -- Guard di WHERE: dua claim paralel → hanya satu yang meng-update.
    UPDATE public.user_missions
    SET claimed = true, claimed_at = now()
    WHERE id = v_user_mission.id AND claimed = false
    RETURNING id INTO v_claimed_id;

    IF v_claimed_id IS NULL THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;

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

-- ── 4. Grants ──────────────────────────────────────────────────────────
-- SAFE: credit_welcome_bonus & charge_metered dicabut dari authenticated.
-- Terdampak: welcome bonus (tetap jalan via edge fn service_role),
-- billing call (tetap jalan via call_billing_tick SECURITY DEFINER),
-- match fee (via _spend_yukcoin_core). TIDAK ada pemanggil client langsung.
REVOKE EXECUTE ON FUNCTION public.credit_welcome_bonus(uuid, text, text, text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.credit_welcome_bonus(uuid, text, text, text)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text)
  TO authenticated, service_role;

-- user_missions: client hanya boleh BACA. Tulis hanya lewat RPC definer.
-- SAFE: tabel misi baru — pembaca client: layar Misi (missions_provider).
-- Penulis: update_mission_progress / claim_mission_reward (SECURITY DEFINER).
DROP POLICY IF EXISTS user_missions_own ON public.user_missions; -- SAFE: diganti policy SELECT-only di baris berikut (tulis lewat RPC definer). Terdampak: layar Misi (baca), claim mission (RPC).
DROP POLICY IF EXISTS user_missions_own_select ON public.user_missions; -- SAFE: idempoten saat migrasi di-apply ulang; akan dibuat ulang di baris berikut.
CREATE POLICY user_missions_own_select ON public.user_missions -- SAFE: ganti FOR ALL → SELECT saja; tulis via RPC definer. Terdampak: layar Misi (baca), claim mission (RPC).
    FOR SELECT USING (user_id = auth.uid());

REVOKE INSERT, UPDATE, DELETE ON public.user_missions FROM anon, authenticated; -- SAFE: mencegah client memalsukan is_completed. Terdampak: misi (progress & claim tetap jalan via RPC definer).
