-- ══════════════════════════════════════════════════════════════════════
-- Withdraw: masa tahan, batas nominal, urutan KYC, misi → bonus, dan
-- penanganan refund Google Play (2026-11-09).
--
-- 1. earned_held(uid, days): penghasilan `earned` (kredit positif, kecuali
--    pengembalian withdraw) dalam `withdraw_hold_days` hari terakhir BELUM
--    bisa ditarik. Default 7 hari = jendela refund cepat Google Play.
-- 2. request_withdraw v3: HELD_BALANCE, DAILY_AMOUNT_LIMIT (default
--    50.000 koin/hari), UNDER_REVIEW (fraud_holds), KYC dicek SEBELUM
--    nomor DANA disimpan (N8).
-- 3. get_earnings_summary: `withdrawable` = setelah masa tahan, + `held`.
-- 4. claim_mission_reward: reward misi selalu `bonus` (semua gender).
-- 5. Refund Play: reverse_play_topup(token) — order → 'refunded', tarik
--    koin pembeli (topup → earned, sebatas saldo), sisa yang tak tertarik
--    dicatat; pembeli + semua penerima koinnya (platform_revenue
--    from_user→to_user sejak pembelian) masuk fraud_holds → withdraw
--    diblokir sampai admin meninjau. Dipanggil edge function
--    play-voided-sync (cron harian, Play Developer API voidedpurchases).
-- ══════════════════════════════════════════════════════════════════════

alter table public.app_settings
  add column if not exists withdraw_hold_days int not null default 7,
  add column if not exists withdraw_max_coins_per_day int not null default 50000;

alter table public.topup_orders drop constraint if exists topup_orders_status_check;
alter table public.topup_orders add constraint topup_orders_status_check
  check (status = any (array['pending','paid','failed','expired','cancelled','refunded']));
alter table public.topup_orders
  add column if not exists refunded_at timestamptz,
  add column if not exists refund_shortfall int not null default 0;

create table if not exists public.fraud_holds (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  ref_id text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  resolve_note text
);
create unique index if not exists fraud_holds_open_uq
  on public.fraud_holds (user_id, reason, coalesce(ref_id, ''))
  where resolved_at is null;
alter table public.fraud_holds enable row level security;
-- Tanpa policy: hanya fungsi definer / service_role yang menyentuh.

-- ── Masa tahan ──────────────────────────────────────────────────────────
create or replace function public.earned_held(p_uid uuid, p_days int)
returns int
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(sum(amount), 0)::int
    from public.coin_ledger
   where user_id = p_uid
     and bucket = 'earned'
     and amount > 0
     and type <> 'withdraw_refund'
     and created_at > now() - make_interval(days => greatest(p_days, 0));
$function$;
revoke execute on function public.earned_held(uuid, int) from public, anon, authenticated;

-- ── request_withdraw v3 (basis: definisi LIVE) ─────────────────────────
-- menyentuh: request_withdraw
create or replace function public.request_withdraw(p_coins integer, p_dana_number text DEFAULT NULL::text, p_dana_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
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
    v_require_kyc boolean;
    v_dana_cd_hours int;
    v_dana_free timestamptz;
    v_hold_days int;
    v_max_coins_day int;
    v_held int;
    v_available int;
    v_today_coins int;
    v_day_start timestamptz :=
      (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
         AT TIME ZONE 'Asia/Jakarta');
begin
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

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
           coalesce(withdraw_min_account_age_hours, 72),
           coalesce(withdraw_require_kyc, true),
           coalesce(withdraw_dana_change_cooldown_hours, 168),
           coalesce(withdraw_hold_days, 7),
           coalesce(withdraw_max_coins_per_day, 50000)
      INTO v_min_coins, v_rate, v_fee_pct, v_fee_min,
           v_max_day, v_min_interval, v_min_age,
           v_require_kyc, v_dana_cd_hours,
           v_hold_days, v_max_coins_day
      FROM public.app_settings WHERE id = 'global';

    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

    -- 2026-11-01 (190000): HANYA bucket `earned` yang bisa ditarik.
    -- Koin `bonus` (gratis) tidak boleh dicairkan jadi uang.
    SELECT coalesce(sum(amount) filter (where bucket = 'earned'), 0) INTO v_total
      FROM public.coin_ledger WHERE user_id = v_uid;

    IF v_total < p_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INSUFFICIENT_BALANCE',
            'balance', v_total);
    END IF;

    -- 2026-11-09: masa tahan — penghasilan v_hold_days hari terakhir belum
    -- bisa dicairkan (jendela refund Google Play / sengketa).
    v_held := public.earned_held(v_uid, v_hold_days);
    v_available := greatest(0, v_total - v_held);
    IF v_available < p_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'HELD_BALANCE',
            'available', v_available, 'held', least(v_held, v_total),
            'hold_days', v_hold_days);
    END IF;

    -- 2026-11-09: akun ditahan (mis. terkait pembelian Play yang di-refund).
    IF EXISTS (SELECT 1 FROM public.fraud_holds
                WHERE user_id = v_uid AND resolved_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'UNDER_REVIEW');
    END IF;

    SELECT created_at INTO v_created_at FROM public.profiles WHERE id = v_uid;
    IF v_created_at IS NOT NULL
       AND v_created_at > now() - make_interval(hours => v_min_age) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ACCOUNT_TOO_NEW',
            'min_age_hours', v_min_age);
    END IF;

    -- (a) DIPULIHKAN: pengajuan yang DITOLAK tidak lagi menghitung kuota
    -- harian maupun cooldown. Tanpa `status <> 'rejected'`, user yang kalah
    -- satu kali harus menunggu 1 jam dan kehabisan kuota 3/hari padahal
    -- tidak ada uang yang keluar.
    SELECT count(*) INTO v_today_count
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND created_at >= v_day_start
       AND status <> 'rejected';
    IF v_today_count >= v_max_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_LIMIT',
            'max_per_day', v_max_day);
    END IF;

    -- 2026-11-09: batas NOMINAL per hari (selain jumlah request).
    SELECT coalesce(sum(coin_amount), 0) INTO v_today_coins
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND created_at >= v_day_start
       AND status <> 'rejected';
    IF v_today_coins + p_coins > v_max_coins_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_AMOUNT_LIMIT',
            'max_coins_per_day', v_max_coins_day,
            'remaining', greatest(0, v_max_coins_day - v_today_coins));
    END IF;

    -- N8 (2026-11-09): gerbang KYC SEBELUM menyimpan nomor DANA — dulu
    -- request yang ditolak KYC tetap menyimpan nomor & memulai cooldown.
    IF v_require_kyc AND NOT EXISTS (
        SELECT 1 FROM public.kyc_requests
         WHERE user_id = v_uid AND status = 'approved') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'KYC_REQUIRED');
    END IF;

    SELECT max(created_at) INTO v_last_req
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND status <> 'rejected';
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
        v_name := nullif(trim(p_dana_name), '');
        IF v_name IS NULL OR length(v_name) < 3 THEN
            RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NAME');
        END IF;

        -- B3: Cooldown ganti nomor — nomor yang BERBEDA dari tersimpan
        -- tak boleh diganti sebelum `withdraw_dana_change_cooldown_hours`
        -- sejak updated_at. Nomor sama / hanya ganti nama → bebas.
        SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
        IF FOUND AND v_acc.dana_number IS DISTINCT FROM v_num
           AND v_acc.updated_at > now() - make_interval(hours => v_dana_cd_hours) THEN
            v_dana_free := v_acc.updated_at + make_interval(hours => v_dana_cd_hours);
            RETURN jsonb_build_object('ok', false,
                'error', 'DANA_CHANGE_COOLDOWN',
                'cooldown_until', v_dana_free,
                'cooldown_hours', v_dana_cd_hours);
        END IF;

        INSERT INTO public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
        VALUES (v_uid, v_num, v_name, now())
        ON CONFLICT (user_id) DO UPDATE SET
            dana_number = excluded.dana_number,
            dana_name = excluded.dana_name,
            updated_at = case
              -- updated_at maju HANYA saat nomor berubah → cooldown diukur
              -- dari ganti nomor terakhir, bukan edit nama.
              when withdraw_accounts.dana_number is distinct from excluded.dana_number
                then now()
              else withdraw_accounts.updated_at
            end;
    ELSE
        SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'error', 'NO_ACCOUNT');
        END IF;
        v_num := v_acc.dana_number;
        v_name := v_acc.dana_name;
    END IF;

    v_gross := p_coins * v_rate;
    -- (b) DIPULIHKAN: bulatkan ke atas agar SAMA dengan preview client
    -- (WithdrawQuote.calc memakai round()). Dulu server memotong lewat
    -- pembagian integer → dialog konfirmasi menjanjikan Rp 1 lebih besar.
    v_fee := round((v_gross * v_fee_pct) / 100.0);
    IF v_fee < v_fee_min THEN v_fee := v_fee_min; END IF;
    IF v_fee > v_gross THEN v_fee := v_gross; END IF;
    v_net := v_gross - v_fee;

    INSERT INTO public.withdrawal_requests
        (user_id, coin_amount, payout_idr, gross_idr, fee_idr, rate,
         status, pay_method, pay_account, pay_holder)
    VALUES
        (v_uid, p_coins, v_net, v_gross, v_fee, v_rate,
         'pending', 'ewallet', v_num, v_name)
    RETURNING id INTO v_req_id;

    -- SATU-SATUNYA titik debit. HANYA bucket `earned`.
    PERFORM public.ledger_spend_earned(v_uid, 'withdraw', p_coins, v_req_id::text);

    INSERT INTO public.point_events (user_id, event, amount, metadata)
    VALUES (v_uid, 'withdraw', -p_coins, jsonb_build_object('request', v_req_id));

    RETURN jsonb_build_object('ok', true, 'id', v_req_id,
        'coins', p_coins, 'rate', v_rate,
        'gross_idr', v_gross, 'fee_idr', v_fee, 'net_idr', v_net,
        'dana_number', v_num, 'dana_name', v_name,
        'status', 'pending');
END;
$function$;

-- ── get_earnings_summary (basis: definisi LIVE) ─────────────────────────
-- menyentuh: get_earnings_summary
create or replace function public.get_earnings_summary(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    result jsonb;
    v_total bigint;
    v_weekly bigint;
    v_today bigint;
    v_gift bigint;
    v_mission bigint;
    v_private_call bigint;
    v_match_call bigint;
    v_other bigint;
    v_withdrawable bigint;
    v_held bigint := 0;
    v_hold_days int;
    v_total_balance bigint;
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
    v_day_start timestamptz;
    v_week_start timestamptz;
BEGIN
    if coalesce(auth.role(), '') <> 'service_role'
       and auth.uid() is not null
       and p_user_id is distinct from auth.uid() then
        raise exception 'Forbidden: tidak boleh membaca saldo user lain'
            using errcode = '42501';
    end if;

    -- Awal hari/minggu dalam Asia/Jakarta, sebagai timestamptz. Bandingkan
    -- timestamptz dengan timestamptz — `date_trunc('day', now() at time zone
    -- …)` mengembalikan timestamp tanpa zona yang lalu dibandingkan dengan
    -- kolom timestamptz → salah tafsir (terbukti: baris 23:29 UTC di hari
    -- berikutnya WIB tidak terhitung).
    v_day_start  := (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
                       AT TIME ZONE 'Asia/Jakarta');
    v_week_start := ((date_trunc('week',
                       (now() AT TIME ZONE 'Asia/Jakarta'))::timestamp)
                       AT TIME ZONE 'Asia/Jakarta');

    SELECT
        COALESCE(SUM(l.amount), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.created_at >= v_week_start), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.created_at >= v_day_start), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.type IN ('gift_recv','coin_received')), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.type = 'mission_reward'), 0),
        -- Privasi = income call_* yang ref_id-nya BUKAN call random.
        COALESCE(SUM(l.amount) FILTER (
            WHERE l.type IN ('call_audio_income','call_video_income',
                             'private_call_income')
              AND rc.id is null), 0),
        -- Match = tipe match_call_income ATAU income call_* dari call random.
        COALESCE(SUM(l.amount) FILTER (
            WHERE l.type = 'match_call_income'
               OR (l.type IN ('call_audio_income','call_video_income')
                   AND rc.id is not null)), 0),
        COALESCE(SUM(l.amount) FILTER (
            WHERE l.type NOT IN ('gift_recv','coin_received','mission_reward',
                                 'call_audio_income','call_video_income',
                                 'private_call_income','match_call_income')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission,
         v_private_call, v_match_call, v_other
    FROM public.coin_ledger l
    LEFT JOIN public.calls rc
      ON rc.id::text = l.ref_id AND rc.kind = 'random'
    WHERE l.user_id = p_user_id
      AND l.amount > 0
      AND l.type IN (
            'gift_recv','coin_received',
            'mission_reward',
            'call_audio_income','call_video_income',
            'private_call_income','match_call_income',
            'photo_income','photo_unlock_income',
            'subscribe_income'
      )
      AND coalesce(l.ref_id, '') NOT IN ('t','test-income')
      AND coalesce(l.ref_id, '') NOT LIKE 'cleanup\_%'
      AND coalesce(l.ref_id, '') NOT LIKE 'female_bonus_reset\_%';

    -- 2026-11-02: yang bisa DITARIK = bucket `earned` saja (sama dengan
    -- validasi request_withdraw). `total_balance` = semua bucket, untuk
    -- informasi — jangan tertukar.
    SELECT COALESCE(SUM(amount) FILTER (WHERE bucket = 'earned'), 0)
      INTO v_withdrawable
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

    -- 2026-11-09: kurangi penghasilan yang masih dalam masa tahan.
    SELECT coalesce(withdraw_hold_days, 7) INTO v_hold_days
      FROM public.app_settings WHERE id = 'global';
    v_held := least(greatest(v_withdrawable, 0),
                    public.earned_held(p_user_id, coalesce(v_hold_days, 7)));
    v_withdrawable := greatest(0, v_withdrawable - v_held);

    SELECT COALESCE(SUM(amount), 0) INTO v_total_balance
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

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
        'held', v_held,
        'hold_days', coalesce(v_hold_days, 7),
        'total_balance', v_total_balance,
        'breakdown', jsonb_build_object(
            'private_call', v_private_call,
            'match_call', v_match_call,
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
$function$;

-- ── get_withdraw_config (basis: definisi LIVE) ──────────────────────────
-- menyentuh: get_withdraw_config
create or replace function public.get_withdraw_config()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'rate', coalesce(withdraw_rate_idr, 7),
        'min_coins', coalesce(withdraw_min_coins, 1500),
        'fee_pct', coalesce(withdraw_fee_pct, 5),
        'fee_min_idr', coalesce(withdraw_fee_min_idr, 1000),
        'max_per_day', coalesce(withdraw_max_per_day, 3),
        'min_interval_hours', coalesce(withdraw_min_interval_hours, 1),
        'min_account_age_hours', coalesce(withdraw_min_account_age_hours, 72),
        'require_kyc', coalesce(withdraw_require_kyc, true),
        'dana_change_cooldown_hours',
            coalesce(withdraw_dana_change_cooldown_hours, 168),
        'coin_send_cut_pct', coalesce(coin_send_cut_pct, 30),
        'hold_days', coalesce(withdraw_hold_days, 7),
        'max_coins_per_day', coalesce(withdraw_max_coins_per_day, 50000)
    ) INTO result
    FROM public.app_settings WHERE id = 'global';

    RETURN coalesce(result, jsonb_build_object(
        'rate', 7, 'min_coins', 1500, 'fee_pct', 5, 'fee_min_idr', 1000,
        'max_per_day', 3, 'min_interval_hours', 1, 'min_account_age_hours', 72,
        'require_kyc', true, 'dana_change_cooldown_hours', 168,
        'coin_send_cut_pct', 30, 'hold_days', 7,
        'max_coins_per_day', 50000));
END;
$function$;

-- ── claim_mission_reward (basis: definisi LIVE) ─────────────────────────
-- menyentuh: claim_mission_reward
create or replace function public.claim_mission_reward(p_user_id uuid, p_mission_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_reward_bucket text;
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

    -- 2026-11-02: tegakkan gender misi di SERVER juga. Sebelumnya misi
    -- female-only (nyonya_1000) difilter hanya di get_user_missions, jadi
    -- male bisa mengklaimnya lewat RPC langsung.
    SELECT gender INTO v_gender FROM public.profiles WHERE id = p_user_id;
    IF v_mission.gender IS NOT NULL
       AND v_mission.gender <> 'all'
       AND COALESCE(v_gender, 'all') <> v_mission.gender THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

    -- Bucket reward: female → earned (withdrawable); selain female → bonus
    -- (tidak bisa dicairkan, tidak bisa ditransfer). Lihat 20261101190000.
    -- 2026-11-09: reward misi SELALU bonus (tidak bisa dicairkan) untuk
    -- semua gender — dulu female → earned = koin gratis bisa jadi uang
    -- lewat multi-akun.
    v_reward_bucket := 'bonus';

    v_is_coins_mission := (v_mission.target_unit = 'coins');

    IF v_is_coins_mission THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_earned_bal
          FROM public.coin_ledger
         WHERE user_id = p_user_id AND bucket = 'earned';

        v_completed := (v_earned_bal >= v_mission.target_value);
        IF NOT v_completed THEN
            RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
        END IF;

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
    VALUES (p_user_id, v_reward_bucket, 'mission_reward', v_mission.reward_coins, p_mission_key);

    SELECT points INTO v_new_points
    FROM public.profiles
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'coins', v_mission.reward_coins,
        'bucket', v_reward_bucket,
        'total_points', v_new_points
    );
END;
$function$;

-- ── Refund Google Play ──────────────────────────────────────────────────
create or replace function public.reverse_play_topup(p_purchase_token text,
                                                     p_reason text default 'voided')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o record; t int; e int; take int; need int; n_flag int := 0;
begin
  select * into o from public.topup_orders
   where purchase_token = p_purchase_token for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;
  if o.status = 'refunded' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  perform pg_advisory_xact_lock(hashtext('wallet:' || o.user_id::text));
  select coalesce(sum(amount) filter (where bucket = 'topup'), 0),
         coalesce(sum(amount) filter (where bucket = 'earned'), 0)
    into t, e
    from public.coin_ledger where user_id = o.user_id;

  need := o.coins;
  take := least(greatest(t, 0), need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
    values (o.user_id, 'topup', 'play_refund', -take, o.id,
            jsonb_build_object('reason', p_reason));
    need := need - take;
  end if;
  take := least(greatest(e, 0), need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
    values (o.user_id, 'earned', 'play_refund', -take, o.id,
            jsonb_build_object('reason', p_reason));
    need := need - take;
  end if;

  update public.topup_orders
     set status = 'refunded', refunded_at = now(), refund_shortfall = need
   where id = o.id;

  -- Tahan pembeli + semua penerima koinnya sejak pembelian.
  insert into public.fraud_holds (user_id, reason, ref_id)
  select distinct u, 'play_refund', o.id
    from (select o.user_id as u
          union
          select pr.to_user from public.platform_revenue pr
           where pr.from_user = o.user_id
             and pr.to_user is not null
             and pr.created_at >= coalesce(o.paid_at, o.created_at)) x
  on conflict do nothing;
  get diagnostics n_flag = row_count;

  return jsonb_build_object('ok', true, 'order_id', o.id, 'coins', o.coins,
    'shortfall', need, 'flagged', n_flag);
end;
$function$;
revoke execute on function public.reverse_play_topup(text, text) from public, anon, authenticated;

-- ── Admin: lihat & selesaikan penahanan ─────────────────────────────────
create or replace function public.admin_fraud_holds(p_open_only boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select h.id, h.user_id, h.reason, h.ref_id, h.created_at, h.resolved_at,
           h.resolve_note, p.nickname, p.email
      from public.fraud_holds h
      left join public.profiles p on p.id = h.user_id
     where (not p_open_only or h.resolved_at is null)
     limit 200
  ) x;
  return res;
end; $function$;

create or replace function public.admin_resolve_fraud_hold(p_id bigint, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;
  update public.fraud_holds
     set resolved_at = now(), resolved_by = auth.uid(), resolve_note = p_note
   where id = p_id and resolved_at is null;
  return jsonb_build_object('ok', found);
end; $function$;
revoke execute on function public.admin_fraud_holds(boolean) from public, anon;
revoke execute on function public.admin_resolve_fraud_hold(bigint, text) from public, anon;
grant execute on function public.admin_fraud_holds(boolean) to authenticated;
grant execute on function public.admin_resolve_fraud_hold(bigint, text) to authenticated;

-- ── Cron harian: sinkron voided purchases dari Google Play ──────────────
select cron.unschedule('play-voided-sync')
 where exists (select 1 from cron.job where jobname = 'play-voided-sync');
select cron.schedule('play-voided-sync', '40 2 * * *', $cron$
  select net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/play-voided-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-app-secret', (select app_shared_secret from public.app_settings where id = 'global')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$cron$);
