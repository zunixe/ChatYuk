-- ============================================================
-- 20261101190000_paid_only_economy.sql
-- TUTUP TIGA JALUR KOIN GRATIS → UANG (audit peredaran koin 2026-11-01).
--
-- CATATAN URUTAN: file ini HARUS di-apply SETELAH
-- 20261101180000_economy_consistency_fixes.sql — file itu me-replace
-- `request_withdraw` dari salinan lama (masih `ledger_spend` bonus-first)
-- dan akan membuka kembali jalur L2 di bawah kalau di-apply setelah ini.
--
-- Latar: `send_gift`, `unlock_photo`, `subscribe_creator`, `send_coins`
-- sudah wajib koin beli/penghasilan (topup+earned). Tapi tiga jalur
-- masih memakai `ledger_spend` yang debit bucket `bonus` (gratis) DULU:
--
-- L1. charge_metered (tagihan call): bonus male bayar menit call →
--     30% net menjadi `earned` female → withdrawable Rp 7/koin.
--     Sumber bonus tak terbatas (welcome 200 + streak harian 25–100 +
--     level reward + admin_mass_bonus) → kerugian tak berbentuk.
-- L2. request_withdraw: cek saldo TOTAL (bonus+topup+earned) dan debit
--     via ledger_spend (bonus dulu) → female pemegang bonus historis
--     bisa mencairkan koin gratis. UI sudah gate `earned`, server tidak.
-- L3. claim_mission_reward: reward misi SELALU bucket `earned` untuk
--     siapa pun (kolom missions.gender = 'all' untuk hampir semua misi).
--     Male klaim misi → earned → kirim koin/gift ke female → withdraw.
--     Misi harian 10–25 koin/hari → potensi pencetakan cash harian.
--
-- Perbaikan:
--   • charge_metered → ledger_spend_paid (topup→earned), precheck
--     yukcoin_paid_total; call_billing_tick afford-check pakai paid.
--   • request_withdraw → cek + debit HANYA bucket `earned`
--     (helper baru ledger_spend_earned).
--   • claim_mission_reward → female: `earned` (sesuatu desain, female
--     penghasilnya dari bucket ini); selain female: `bonus` (tidak
--     withdrawable, tidak bisa ditransfer/bayar fitur).
--
-- TIDAK diubah (sudah aman): gift/foto/subscribe/kirim-koin (paid-only),
-- fee match 2 koin (hangus → platform_revenue), room create/extend &
-- chat foto (burn tanpa penerima).
-- ============================================================

-- menyentuh: charge_metered, call_billing_tick, request_withdraw, claim_mission_reward

-- ── 0a. yukcoin_paid_total — saldo yang boleh bayar fitur ───────────────
-- Cermin `paidBalance` di client (topupBalance + earnedBalance).
create or replace function public.yukcoin_paid_total(p_user uuid)
returns int
language sql
security definer
set search_path = public
as $$
  select coalesce(sum(amount) filter (where bucket in ('topup','earned')), 0)::int
    from public.coin_ledger where user_id = p_user;
$$;
revoke execute on function public.yukcoin_paid_total(uuid) from public, anon;
grant execute on function public.yukcoin_paid_total(uuid) to authenticated, service_role;

-- ── 0b. ledger_spend_earned — debit HANYA bucket earned ─────────────────
-- Dipakai request_withdraw: koin bonus (gratis) tidak boleh jadi uang.
-- Advisory lock per-user sama seperti ledger_spend (anti double-spend).
create or replace function public.ledger_spend_earned(
  p_user uuid, p_type text, p_amount int, p_ref text default null
) returns int language plpgsql security definer set search_path = public as $$
declare e int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;

  perform pg_advisory_xact_lock(hashtext('wallet:' || p_user::text));

  select coalesce(sum(amount) filter (where bucket='earned'), 0) into e
    from coin_ledger where user_id = p_user;
  if e < p_amount then
    raise exception 'Not enough earned' using errcode = '22023';
  end if;

  insert into coin_ledger(user_id, bucket, type, amount, ref_id)
    values (p_user, 'earned', p_type, -p_amount, p_ref);

  return public.wallet_sync_points(p_user);
end; $$;
revoke execute on function public.ledger_spend_earned(uuid, text, int, text) from public, anon, authenticated;
grant execute on function public.ledger_spend_earned(uuid, text, int, text) to service_role;

-- ── 1. charge_metered — WAJIB koin beli/penghasilan (L1) ────────────────
-- Badan sama dengan 20261101100100, KECUALI:
--   • precheck saldo: yukcoin_total → yukcoin_paid_total
--   • debit: ledger_spend (bonus dulu) → ledger_spend_paid (topup→earned)
-- Sisanya (guard callee, cut 70%, income female `earned`, platform_revenue,
-- kill-switch points_enabled) tidak berubah.
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

  -- 2026-11-01: call WAJIB pakai koin beli/penghasilan. Koin gratis
  -- (`bonus`) tidak boleh membayar menit call — 30% net-nya menjadi
  -- `earned` female (withdrawable) = koin gratis berubah jadi uang.
  balance := public.yukcoin_paid_total(p_caller);
  if balance < total then
    raise exception 'Koin beli/penghasilan tidak cukup (top-up dulu)'
      using errcode = '22023';
  end if;

  remaining := public.ledger_spend_paid(p_caller, p_feature, total, p_ref);

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
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (p_feature, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, p_feature, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $function$;

-- ── 2. call_billing_tick — afford-check pakai saldo paid (L1) ───────────
-- Badan sama dengan 20261031110011, KECUALI precheck kemampuan bayar:
-- yukcoin_total → yukcoin_paid_total. Male yang hanya punya koin bonus
-- mendapat can_continue=false (bukan exception) saat menit berbayar.
CREATE OR REPLACE FUNCTION public.call_billing_tick(p_call_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  c record;
  feat text; unit_cost int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  afford int; charge_n int;
  remaining int; v_paid int;
  points_on boolean;
  v_caller_gender text;
  v_free_limit int;
  v_free_used numeric;
  v_free_seconds_left int := 0;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    return jsonb_build_object(
      'ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  -- ── Caller FEMALE = GRATIS (batas menit/hari) ──
  select gender into v_caller_gender from public.profiles where id = me;
  if v_caller_gender = 'female' then
    select coalesce(female_free_call_min_per_day, 30) into v_free_limit
      from app_settings where id = 'global';
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

  feat := case when c.kind = 'random' then 'call_video'
               when c.call_type = 'audio' then 'call_audio'
               else 'call_video' end;

  select case when c.kind = 'random' then call_video_cost_per_min
              when c.call_type = 'audio' then call_audio_cost_per_min
              else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);

  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;

  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);

  -- 2026-10-31: MATCH (kind='random') → menit ke-1 GRATIS.
  -- Call biasa: pembulatan ke atas (detik 1–60 sudah ditagih 1 menit).
  if c.kind = 'random' then
    billable_minutes := greatest(0, elapsed_sec / 60 - 1);  -- 0–119 s = 0
    v_free_seconds_left := greatest(0, 120 - elapsed_sec);
  else
    billable_minutes := (elapsed_sec + 59) / 60;
  end if;

  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = me and feature = feat and ref_id = p_call_id::text;

  to_bill := greatest(0, billable_minutes - already_billed);
  remaining := public.yukcoin_total(me);
  -- 2026-11-01: kemampuan bayar dihitung dari koin BELI/penghasilan
  -- (charge_metered menolak bonus). Bonus-only → can_continue=false.
  v_paid := public.yukcoin_paid_total(me);

  if to_bill > 0 then
    if v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
    end if;
    afford := v_paid / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public.charge_metered(me, feat, p_call_id::text, charge_n, c.callee_id);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select me, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g,
                                  'call_type', c.call_type,
                                  'kind', coalesce(c.kind, 'private'))
        from generate_series(1, charge_n) g;
      already_billed := already_billed + charge_n;
      remaining := public.yukcoin_total(me);
      v_paid := public.yukcoin_paid_total(me);
    end if;
    if charge_n < to_bill or v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
    'remaining', remaining, 'free_seconds_left', v_free_seconds_left);
end; $function$;

-- ── 3. request_withdraw — HANYA bucket earned (L2) ──────────────────────
-- Badan sama dengan 20261101100000, KECUALI:
--   • cek saldo: semua bucket → bucket `earned` saja
--   • debit: ledger_spend (bonus dulu) → ledger_spend_earned
-- Bonus (gratis) tidak bisa dicairkan jadi uang. Refund di
-- admin_withdraw_process sudah reverse per-bucket → tidak berubah.
CREATE OR REPLACE FUNCTION public.request_withdraw(p_coins integer, p_dana_number text DEFAULT NULL::text, p_dana_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    -- Serialisasi per user: cek saldo + debit + insert pengajuan harus
    -- atomik. Tanpa ini dua pengajuan paralel sama-sama lolos cek saldo.
    PERFORM pg_advisory_xact_lock(hashtext('withdraw:' || v_uid::text));

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
      FROM app_settings WHERE id = 'global';

    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

    -- 2026-11-01: withdraw HANYA dari bucket `earned` (penghasilan).
    -- Koin `bonus` (gratis) tidak boleh dicairkan jadi uang.
    SELECT coalesce(sum(amount) filter (where bucket='earned'), 0) INTO v_total
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

    IF p_dana_number IS NOT NULL AND p_dana_name IS NOT NULL THEN
        v_num := regexp_replace(p_dana_number, '[^0-9]', '', 'g');
        IF v_num !~ '^(08|62)[0-9]{8,13}$' THEN
            RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NUMBER');
        END IF;
        IF v_num LIKE '62%' THEN v_num := '0' || substring(v_num from 3); END IF;
        v_name := nullif(trim(coalesce(p_dana_name, '')), '');
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

    -- SATU-SATUNYA titik debit (lihat admin_withdraw_process).
    -- HANYA bucket `earned` — bonus tidak bisa dicairkan.
    PERFORM public.ledger_spend_earned(v_uid, 'withdraw', p_coins, v_req_id::text);

    INSERT INTO public.point_events (user_id, event, amount, metadata)
    VALUES (v_uid, 'withdraw', -p_coins, jsonb_build_object('request', v_req_id));

    RETURN jsonb_build_object('ok', true, 'id', v_req_id,
        'coins', p_coins, 'rate', v_rate,
        'gross_idr', v_gross, 'fee_idr', v_fee, 'net_idr', v_net,
        'dana_number', v_num, 'dana_name', v_name,
        'status', 'pending');
END; $function$;

-- ── 4. claim_mission_reward — bucket reward by gender (L3) ──────────────
-- Badan sama dengan 20261101170000, KECUALI bucket kredit:
--   • female  → `earned` (withdrawable — sumber penghasilan female)
--   • lainnya → `bonus`  (tidak withdrawable, tidak bisa ditransfer
--     atau bayar fitur setelah L1/L2 ditutup)
-- Tanpa ini male klaim misi harian (10–25 koin) → earned → kirim koin
-- ke female → withdraw: koin misi gratis jadi uang.
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
    v_earned_bal bigint;
    v_is_coins_mission boolean := false;
    v_completed boolean;
    v_gender text;
    v_bucket text;
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

    -- 2026-11-01: bucket reward menurut gender pemilik misi.
    -- Female → earned (withdrawable); selain female → bonus (aman:
    -- tidak withdrawable & tidak bisa ditransfer/bayar fitur).
    SELECT gender INTO v_gender FROM public.profiles WHERE id = p_user_id;
    v_bucket := CASE WHEN v_gender = 'female' THEN 'earned' ELSE 'bonus' END;

    -- Misi bertarget koin: kelulusan dihitung dari saldo, bukan dari baris
    -- user_missions (yang tidak pernah ditulis untuk misi ini).
    v_is_coins_mission := (v_mission.target_unit = 'coins');

    IF v_is_coins_mission THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_earned_bal
          FROM public.coin_ledger
         WHERE user_id = p_user_id AND bucket = 'earned';

        v_completed := (v_earned_bal >= v_mission.target_value);
        IF NOT v_completed THEN
            RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
        END IF;

        -- Pastikan baris ada supaya klaim bisa ditandai (anti dobel).
        INSERT INTO public.user_missions
            (user_id, mission_id, progress, is_completed, completed_at, period_date)
        VALUES (
            p_user_id,
            v_mission.id,
            LEAST(v_earned_bal, v_mission.target_value)::int,
            true,
            now(),
            v_period
        )
        ON CONFLICT (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date))
        DO UPDATE SET
            progress = LEAST(v_earned_bal, v_mission.target_value)::int,
            is_completed = true,
            completed_at = COALESCE(user_missions.completed_at, now());
    ELSE
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
    END IF;

    -- Guard di WHERE: dua klaim paralel → hanya satu yang meng-update.
    UPDATE public.user_missions
    SET claimed = true, claimed_at = now()
    WHERE user_id = p_user_id
      AND mission_id = v_mission.id
      AND COALESCE(period_date, '1970-01-01'::date) = COALESCE(v_period, '1970-01-01'::date)
      AND claimed = false
    RETURNING id INTO v_claimed_id;

    IF v_claimed_id IS NULL THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;

    INSERT INTO public.coin_ledger (user_id, bucket, type, amount, ref_id)
    VALUES (p_user_id, v_bucket, 'mission_reward', v_mission.reward_coins, p_mission_key);

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

REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;
