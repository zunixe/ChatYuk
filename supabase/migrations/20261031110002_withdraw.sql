-- ══════════════════════════════════════════════════════════════════════
-- Fase 2 — Withdraw (cash-out) ke DANA
--
-- Model: FEMALE menarik koin dari bucket `earned` (penghasilan dari aktivitas
-- male + reward misi) menjadi Rupiah ke akun DANA. Manual approve oleh admin.
--
-- Reuse tabel `withdrawal_requests` (dari fitur finansial lama, kosong):
--   coin_amount  = koin ditarik
--   gross_idr    = coin_amount × rate            (BARU)
--   fee_idr      = max(gross × fee_pct%, fee_min) (BARU)
--   payout_idr   = gross − fee  (yang benar-benar ditransfer)
--   pay_method   = 'ewallet'  (DANA)
--   pay_account  = nomor DANA
--   pay_holder   = nama pemilik
--   status       = 'pending' | 'paid' | 'rejected'
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. Setting withdraw ──
ALTER TABLE public.app_settings
    ADD COLUMN IF NOT EXISTS withdraw_fee_pct int NOT NULL DEFAULT 5;

ALTER TABLE public.app_settings
    ADD COLUMN IF NOT EXISTS withdraw_fee_min_idr int NOT NULL DEFAULT 1000;

-- Minimum dinaikkan 1000 → 1500 koin (Rp 10.500) agar di atas biaya admin.
UPDATE public.app_settings
    SET withdraw_min_coins = 1500
    WHERE id = 'global' AND coalesce(withdraw_min_coins, 0) < 1500;

-- ── 2. Kolom baru di withdrawal_requests ──
ALTER TABLE public.withdrawal_requests
    ADD COLUMN IF NOT EXISTS gross_idr int;

ALTER TABLE public.withdrawal_requests
    ADD COLUMN IF NOT EXISTS fee_idr int;

-- Backfill baris lama (0 baris, aman).
UPDATE public.withdrawal_requests
    SET gross_idr = coalesce(payout_idr, 0),
        fee_idr = 0
    WHERE gross_idr IS NULL OR fee_idr IS NULL;

ALTER TABLE public.withdrawal_requests
    ALTER COLUMN gross_idr SET DEFAULT 0;

ALTER TABLE public.withdrawal_requests
    ALTER COLUMN fee_idr SET DEFAULT 0;

-- ── 3. Tabel akun DANA tersimpan ──
CREATE TABLE IF NOT EXISTS public.withdraw_accounts (
    user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    dana_number text NOT NULL,
    dana_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.withdraw_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY withdraw_accounts_own ON public.withdraw_accounts -- SAFE: tabel BARU `withdraw_accounts` (akun DANA per user), RLS own-only; tidak menyentuh tabel bersama
    FOR ALL USING (user_id = auth.uid());

-- ── 4. RPC: simpan / baca akun DANA ──
CREATE OR REPLACE FUNCTION public.save_withdraw_account(
    p_dana_number text,
    p_dana_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_num text;
    v_name text;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Normalisasi nomor: buang spasi/strip, wajib 08xx atau 62xx, 10-14 digit.
    v_num := regexp_replace(coalesce(p_dana_number, ''), '[^0-9]', '', 'g');
    IF v_num !~ '^(08|62)[0-9]{8,13}$' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NUMBER');
    END IF;
    -- 62xx → 0xx (format DANA domestik).
    IF v_num LIKE '62%' THEN
        v_num := '0' || substring(v_num from 3);
    END IF;

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

    RETURN jsonb_build_object('ok', true,
        'dana_number', v_num, 'dana_name', v_name);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_withdraw_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_rec record;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    SELECT * INTO v_rec FROM public.withdraw_accounts WHERE user_id = v_uid;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', true, 'has_account', false);
    END IF;

    RETURN jsonb_build_object('ok', true, 'has_account', true,
        'dana_number', v_rec.dana_number, 'dana_name', v_rec.dana_name);
END;
$$;

-- ── 5. RPC: ajukan withdraw ──
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
    v_earned int;
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

    -- Hanya FEMALE yang boleh withdraw (male tidak punya bucket `earned`).
    SELECT gender INTO v_gender FROM public.profiles WHERE id = v_uid;
    IF v_gender IS DISTINCT FROM 'female' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'FEMALE_ONLY');
    END IF;

    -- Konfigurasi.
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

    -- Validasi jumlah.
    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

    -- Saldo `earned` (sumber-sumber withdraw HANYA bucket ini).
    SELECT coalesce(sum(amount) filter (where bucket = 'earned'), 0)
      INTO v_earned
      FROM public.coin_ledger WHERE user_id = v_uid;

    IF v_earned < p_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INSUFFICIENT_EARNED',
            'earned', v_earned);
    END IF;

    -- Umur akun.
    SELECT created_at INTO v_created_at FROM public.profiles WHERE id = v_uid;
    IF v_created_at IS NOT NULL
       AND v_created_at > now() - make_interval(hours => v_min_age) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ACCOUNT_TOO_NEW',
            'min_age_hours', v_min_age);
    END IF;

    -- Limit harian.
    SELECT count(*) INTO v_today_count
      FROM public.withdrawal_requests
     WHERE user_id = v_uid AND created_at >= current_date;
    IF v_today_count >= v_max_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_LIMIT',
            'max_per_day', v_max_day);
    END IF;

    -- Interval minimum antar request.
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
        -- Simpan untuk pemakaian berikutnya.
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

    -- Hitung nominal.
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

-- ── 6. RPC: admin proses (approve / reject) ──
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
    v_earned int;
    v_new_points int;
BEGIN
    IF v_admin_email <> 'zunixe@gmail.com' THEN
        RAISE EXCEPTION 'NOT_ADMIN: hanya admin';
    END IF;

    SELECT * INTO v_req FROM public.withdrawal_requests WHERE id = p_request_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    IF v_req.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED',
            'status', v_req.status);
    END IF;

    IF NOT p_approve THEN
        UPDATE public.withdrawal_requests
        SET status = 'rejected',
            admin_note = nullif(trim(coalesce(p_note, '')), ''),
            reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
            reviewed_at = now(),
            updated_at = now()
        WHERE id = p_request_id;
        RETURN jsonb_build_object('ok', true, 'status', 'rejected');
    END IF;

    -- APPROVE: pastikan saldo `earned` MASIH cukup (bisa berubah sejak request).
    SELECT coalesce(sum(amount) filter (where bucket = 'earned'), 0)
      INTO v_earned
      FROM public.coin_ledger WHERE user_id = v_req.user_id;

    IF v_earned < v_req.coin_amount THEN
        UPDATE public.withdrawal_requests
        SET status = 'rejected',
            admin_note = 'saldo earned tidak cukup saat approve',
            reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
            reviewed_at = now(),
            updated_at = now()
        WHERE id = p_request_id;
        RETURN jsonb_build_object('ok', false, 'error', 'INSUFFICIENT_AT_APPROVE',
            'earned', v_earned, 'needed', v_req.coin_amount);
    END IF;

    -- Debit bucket `earned`. Trigger trg_coin_ledger_balance() otomatis
    -- mengurangi profiles.points & earned_balance.
    INSERT INTO public.coin_ledger
        (user_id, bucket, type, amount, ref_id, metadata)
    VALUES
        (v_req.user_id, 'earned', 'withdraw', -v_req.coin_amount,
         v_req.id::text,
         jsonb_build_object('gross_idr', v_req.gross_idr, 'fee_idr', v_req.fee_idr,
                            'net_idr', v_req.payout_idr, 'pay', 'dana',
                            'account', v_req.pay_account));

    SELECT points INTO v_new_points FROM public.profiles WHERE id = v_req.user_id;

    UPDATE public.withdrawal_requests
    SET status = 'paid',
        admin_note = nullif(trim(coalesce(p_note, '')), ''),
        reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id;

    RETURN jsonb_build_object('ok', true, 'status', 'paid',
        'coins', v_req.coin_amount, 'net_idr', v_req.payout_idr,
        'remaining_points', v_new_points);
END;
$$;

-- ── 7. RPC: riwayat user ──
CREATE OR REPLACE FUNCTION public.get_withdraw_history(p_limit int DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    result jsonb;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    SELECT jsonb_build_object(
        'requests', coalesce((
            SELECT jsonb_agg(row_to_json(w) ORDER BY w.created_at DESC)
            FROM (
                SELECT id, coin_amount, rate, gross_idr, fee_idr, payout_idr,
                       status, pay_method, pay_account, pay_holder,
                       admin_note, created_at, reviewed_at
                  FROM public.withdrawal_requests
                 WHERE user_id = v_uid
                 ORDER BY created_at DESC
                 LIMIT greatest(1, least(coalesce(p_limit, 30), 100))
            ) w
        ), '[]'::jsonb),
        'earned_balance', (
            SELECT coalesce(sum(amount) filter (where bucket = 'earned'), 0)
              FROM public.coin_ledger WHERE user_id = v_uid
        )
    ) INTO result;

    RETURN result;
END;
$$;

-- ── 8. RPC: daftar untuk admin ──
CREATE OR REPLACE FUNCTION public.admin_withdraw_list(
    p_status text DEFAULT 'pending',
    p_limit int DEFAULT 50,
    p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_admin_email text := coalesce(auth.email(), '');
    result jsonb;
    v_total int;
BEGIN
    IF v_admin_email <> 'zunixe@gmail.com' THEN
        RAISE EXCEPTION 'NOT_ADMIN: hanya admin';
    END IF;

    IF p_status IS NULL OR p_status = '' OR p_status = 'all' THEN
        SELECT count(*) INTO v_total FROM public.withdrawal_requests;
    ELSE
        SELECT count(*) INTO v_total FROM public.withdrawal_requests
         WHERE status = p_status;
    END IF;

    SELECT jsonb_build_object(
        'total', v_total,
        'requests', coalesce((
            SELECT jsonb_agg(row_to_json(w) ORDER BY w.created_at DESC)
            FROM (
                SELECT r.id, r.user_id, r.coin_amount, r.rate, r.gross_idr,
                       r.fee_idr, r.payout_idr, r.status, r.pay_method,
                       r.pay_account, r.pay_holder, r.admin_note, r.tx_id,
                       r.created_at, r.reviewed_at,
                       p.nickname, p.email
                  FROM public.withdrawal_requests r
                  JOIN public.profiles p ON p.id = r.user_id
                 WHERE (p_status IS NULL OR p_status = '' OR p_status = 'all'
                        OR r.status = p_status)
                 ORDER BY r.created_at DESC
                 LIMIT greatest(1, least(coalesce(p_limit, 50), 200))
                OFFSET greatest(0, coalesce(p_offset, 0))
            ) w
        ), '[]'::jsonb)
    ) INTO result;

    RETURN result;
END;
$$;

-- ── 9. get_earnings_summary: + field withdrawable ──
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
    v_private_call bigint := 0;
    v_match_call bigint := 0;
    v_message bigint := 0;
    v_gift bigint;
    v_mission bigint;
    v_bonus bigint;
    v_other bigint;
    v_withdrawable bigint;
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
BEGIN
    -- ── Penghasilan dari coin_ledger ──
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= date_trunc('week', now())), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= current_date), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'gift_recv'), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'mission_reward'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type IN ('signup','welcome_anon','daily_login','one_time',
                           'new_chat','room_read','photo_upload')), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type NOT IN ('gift_recv','mission_reward','signup','welcome_anon',
                               'daily_login','one_time','new_chat','room_read',
                               'photo_upload')), 0),
        COALESCE(SUM(amount) FILTER (WHERE bucket = 'earned'), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission, v_bonus, v_other, v_withdrawable
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

    -- Tingkat menjawab panggilan pribadi (sebagai penerima).
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE answered_at IS NOT NULL)
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
            'message', v_message,
            'gift', v_gift,
            'mission', v_mission,
            'bonus', v_bonus,
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

-- ── Grants ──
REVOKE EXECUTE ON FUNCTION public.save_withdraw_account(text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_withdraw_account() FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.request_withdraw(int, text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.admin_withdraw_process(uuid, boolean, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_withdraw_history(int) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.admin_withdraw_list(text, int, int) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;

GRANT EXECUTE ON FUNCTION public.save_withdraw_account(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_withdraw_account() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_withdraw(int, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_withdraw_process(uuid, boolean, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_withdraw_history(int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_withdraw_list(text, int, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;
