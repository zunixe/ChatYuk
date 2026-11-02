-- ============================================================
-- 20261101180000_economy_consistency_fixes.sql
-- Konsistensi & hardening fitur saldo/bonus (lanjutan audit 2026-11-01).
--
-- 1. get_earnings_summary: `breakdown.match_call` & `message` di-hardcode 0
--    padahal `private_call` sudah memasukkan match_call_income → income
--    match muncul di baris "Panggilan Privasi" dan baris "Panggilan Match"
--    SELALU 0. Dipisahkan sekarang.
-- 2. Zona waktu: `current_date`/`date_trunc('week', now())` memakai zona
--    sesi DB (UTC) → "Hari Ini" reset 07:00 WIB. Dipindah ke Asia/Jakarta
--    supaya sama dengan ekonomi lain.
-- 3. `SET search_path` ditambahkan (fungsi SECURITY DEFINER tanpa itu).
-- 4. request_withdraw: kuota harian & cooldown menghitung SEMUA baris apa
--    pun statusnya → pengajuan yang DITOLAK tetap memakan kuota 3/hari dan
--    cooldown 1 jam. Status `rejected` sekarang dikecualikan.
-- 5. WithdrawQuote.calc (client) membulatkan fee, server memotong →
--    selisih 1 Rp di dialog konfirmasi. Server memakai pembulatan yang
--    sama dengan client agar preview = tagihan.
-- ============================================================

-- ── 1-3. get_earnings_summary ──────────────────────────────────────────
-- menyentuh: get_earnings_summary
CREATE OR REPLACE FUNCTION public.get_earnings_summary(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
    -- Batas hari/minggu dalam Asia/Jakarta (bukan UTC sesi DB).
    v_day_start timestamptz;
    v_week_start timestamptz;
BEGIN
    -- Guard anti-IDOR (2026-11-01): hanya boleh membaca milik sendiri.
    if coalesce(auth.role(), '') <> 'service_role'
       and auth.uid() is not null
       and p_user_id is distinct from auth.uid() then
        raise exception 'Forbidden: tidak boleh membaca saldo user lain'
            using errcode = '42501';
    end if;

    v_day_start  := date_trunc('day',  now() AT TIME ZONE 'Asia/Jakarta');
    v_week_start := date_trunc('week', now() AT TIME ZONE 'Asia/Jakarta');

    -- Audit 2026-10-31: whitelist diselaraskan dengan type yang benar-benar
    -- ditulis fungsi ekonomi. Versi lama melewatkan coin_received (kirim
    -- koin antar user), subscribe_income, dan photo_income (unlock_photo
    -- menulis 'photo_income', BUKAR 'photo_unlock_income').
    -- 2026-11-01: private_call & match_call DIPISAH (dulu match ikut ke
    -- private_call dan baris match_call selalu 0).
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= v_week_start), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= v_day_start), 0),
        COALESCE(SUM(amount) FILTER (WHERE type IN ('gift_recv','coin_received')), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'mission_reward'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type IN ('call_audio_income','call_video_income',
                           'private_call_income')), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'match_call_income'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type NOT IN ('gift_recv','coin_received','mission_reward',
                               'call_audio_income','call_video_income',
                               'private_call_income','match_call_income')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission,
         v_private_call, v_match_call, v_other
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
$$;

REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;

-- ── 4. request_withdraw: rejected tidak menghabiskan kuota ─────────────
-- menyentuh: request_withdraw
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
      FROM public.app_settings WHERE id = 'global';

    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

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

    -- 2026-11-01: pengajuan yang DITOLAK tidak lagi menghitung kuota harian
    -- maupun cooldown — dulu user yang kalah satu kali harus menunggu 1 jam
    -- dan kehabisan kuota 3/hari padahal tidak ada uang yang keluar.
    SELECT count(*) INTO v_today_count
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND created_at >= current_date
       AND status <> 'rejected';
    IF v_today_count >= v_max_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_LIMIT',
            'max_per_day', v_max_day);
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
    -- Bulatkan ke atas agar sama dengan preview client (WithdrawQuote.calc
    -- memakai round()). Dulu server memotong → selisih 1 Rp di dialog.
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

    PERFORM public.ledger_spend(v_uid, 'withdraw', p_coins, v_req_id::text);

    INSERT INTO public.point_events (user_id, event, amount, metadata)
    VALUES (v_uid, 'withdraw', -p_coins, jsonb_build_object('request', v_req_id));

    RETURN jsonb_build_object('ok', true, 'id', v_req_id,
        'coins', p_coins, 'rate', v_rate,
        'gross_idr', v_gross, 'fee_idr', v_fee, 'net_idr', v_net,
        'dana_number', v_num, 'dana_name', v_name,
        'status', 'pending');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.request_withdraw(int, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_withdraw(int, text, text) TO authenticated, service_role;
