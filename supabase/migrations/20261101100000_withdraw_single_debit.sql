-- ============================================================
-- 20261101100000_withdraw_single_debit.sql
-- BUGFIX EKONOMI (uang nyata) — koin withdraw hilang.
--
-- Keadaan sebelumnya (dua migrasi bertabrakan):
--   • 20261031110016: request_withdraw MENDEBIT koin saat pengajuan.
--   • 20261031110005: admin_withdraw_process (yang dipanggil app,
--     lib/screens/admin_withdraw_tab.dart) MASIH mendebit lagi saat
--     approve, dan sebelumnya memeriksa `v_total < coin_amount`.
-- Akibatnya saldo sudah terpotong saat request → cek saat approve hampir
-- selalu gagal → status 'INSUFFICIENT_AT_APPROVE', DAN jalur tolak tidak
-- me-refund apa pun. User kehilangan koin tanpa pernah menerima uang.
--
-- Perbaikan:
--   1. SATU titik debit: tetap di request_withdraw (koin terkunci selama
--      pending). admin_withdraw_process TIDAK lagi mendebit.
--   2. Reject/insufficient → refund penuh, tepat sebesar baris ledger
--      'withdraw' milik pengajuan itu (reverse per bucket).
--   3. FOR UPDATE + guarded UPDATE ... WHERE status='pending' → approve
--      ganda tidak mungkin.
--   4. Advisory lock per user di request_withdraw → dua pengajuan paralel
--      tidak bisa over-debit.
-- ============================================================

-- ── 1. request_withdraw — tambah advisory lock per user ────────────────
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

    -- SATU-SATUNYA titik debit (lihat admin_withdraw_process).
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

-- ── 2. admin_withdraw_process — tanpa debit kedua + refund saat tolak ──
CREATE OR REPLACE FUNCTION public.admin_withdraw_process(
    p_request_id uuid,
    p_approve boolean,
    p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_admin_email text := coalesce(auth.email(), '');
    v_req record;
    v_taken record;
    v_refunded bigint := 0;
    v_new_points int;
BEGIN
    IF v_admin_email <> 'zunixe@gmail.com' THEN
        RAISE EXCEPTION 'NOT_ADMIN: hanya admin';
    END IF;

    -- Kunci baris + wajib masih pending → approve/reject ganda ditolak.
    SELECT * INTO v_req
      FROM public.withdrawal_requests
     WHERE id = p_request_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    IF v_req.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED',
            'status', v_req.status);
    END IF;

    IF NOT p_approve THEN
        -- Koin sudah didebit saat request → kembalikan PERSIS sebesar baris
        -- ledger 'withdraw' milik pengajuan ini (reverse per bucket).
        FOR v_taken IN
            SELECT bucket, (-sum(amount))::int AS amt
              FROM public.coin_ledger
             WHERE user_id = v_req.user_id
               AND type = 'withdraw'
               AND ref_id = v_req.id::text
             GROUP BY bucket
            HAVING -sum(amount) > 0
        LOOP
            PERFORM public.ledger_credit(v_req.user_id, v_taken.bucket,
                'withdraw_refund', v_taken.amt, v_req.id::text,
                jsonb_build_object('reason', 'reject', 'note', p_note));
            v_refunded := v_refunded + v_taken.amt;
        END LOOP;

        UPDATE public.withdrawal_requests
        SET status = 'rejected',
            admin_note = nullif(trim(coalesce(p_note, '')), ''),
            reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
            reviewed_at = now(),
            updated_at = now()
        WHERE id = p_request_id AND status = 'pending';

        RETURN jsonb_build_object('ok', true, 'status', 'rejected',
            'refunded', v_refunded);
    END IF;

    -- Approve: TIDAK ada debit. Koin sudah keluar di request_withdraw.
    UPDATE public.withdrawal_requests
    SET status = 'paid',
        admin_note = nullif(trim(coalesce(p_note, '')), ''),
        reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id AND status = 'pending';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED');
    END IF;

    SELECT points INTO v_new_points FROM public.profiles WHERE id = v_req.user_id;

    RETURN jsonb_build_object('ok', true, 'status', 'paid',
        'coins', v_req.coin_amount, 'net_idr', v_req.payout_idr,
        'remaining_points', v_new_points, 'debited', 0);
END;
$$;

-- Grants tetap (fungsi sudah di-grant ke authenticated; admin dicek di badan).
REVOKE EXECUTE ON FUNCTION public.admin_withdraw_process(uuid, boolean, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_withdraw_process(uuid, boolean, text) TO authenticated, service_role;
