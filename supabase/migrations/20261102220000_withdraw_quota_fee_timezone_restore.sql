-- ============================================================
-- 20261102220000_withdraw_quota_fee_timezone_restore.sql
-- PULIHKAN TIGA PERBAIKAN YANG DIBATALKAN OLEH 20261101190000.
--
-- LATAR (penting untuk urutan apply):
-- `20261101190000_paid_only_economy.sql` menyalin `request_withdraw` dari
-- salinan LAMA (sebelum 20261101180000) supaya bisa menutup jalur koin
-- gratis -> uang. Salinan itu benar untuk tujuan utamanya, TAPI diam-diam
-- membuang tiga perbaikan yang sudah ada di 20261101180000:
--
--   (a) kuota harian & cooldown menghitung SEMUA baris apa pun statusnya →
--       pengajuan yang DITOLAK tetap memakan kuota 3/hari + cooldown 1 jam;
--   (b) fee memakai pembagian integer (memotong) sedangkan client
--       membulatkan → dialog konfirmasi bisa selisih 1 Rp;
--   (c) batas "hari" memakai `current_date` (zona sesi DB = UTC) →
--       tidak konsisten dengan perbaikan zona waktu di get_earnings_summary.
--
-- CATATAN UNTUK MIGRASI BERIKUTNYI: bila Anda men-replace fungsi ini lagi,
-- SALIN DARI DEFINISI LIVE (`pg_get_functiondef`), JANGAN dari file lama —
-- itulah cara tiga perbaikan ini hilang.
-- ============================================================

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
    -- Awal hari ini dalam zona waktu USER (Asia/Jakarta) sebagai timestamptz.
    -- Bandingkan timestamptz dengan timestamptz (lihat catatan di
    -- 20261102240000 — membandingkan dengan `date` salah tafsir).
    v_day_start timestamptz :=
      (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
         AT TIME ZONE 'Asia/Jakarta');
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

    -- 2026-11-01 (190000): HANYA bucket `earned` yang bisa ditarik.
    -- Koin `bonus` (gratis) tidak boleh dicairkan jadi uang.
    SELECT coalesce(sum(amount) filter (where bucket = 'earned'), 0) INTO v_total
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

REVOKE EXECUTE ON FUNCTION public.request_withdraw(int, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_withdraw(int, text, text) TO authenticated, service_role;
