-- ============================================================
-- 20261101210000_client_paid_precheck_hardening.sql
-- TUTUP SISA CELAH AUDIT EKONOMI KOIN (review 2026-11-02).
--
-- 1. spend_yukcoin: masih di-grant ke `authenticated` padahal client
--    tidak pernah memanggilnya (pemanggil sah: random_match_join via
--    _spend_yukcoin_core sebagai SECURITY DEFINER). Allowlist core masih
--    memuat 'gift' — dead path tanpa penerima income, tapi grant terbuka
--    berarti client bisa memanggilnya langsung. → REVOKE dari
--    `authenticated` (service_role & definer tetap jalan).
--
-- 2. get_earnings_summary: `v_withdrawable` = SUM(amount) SEMUA bucket.
--    Sejak 20261101190000, yang bisa ditarik HANYA bucket `earned`
--    (request_withdraw menolak bonus). Koin `bonus` — termasuk reward
--    misi male — menggelembungkan angka "bisa ditarik" di layar Saldo.
--    → filter bucket `earned`.
--
-- Badan get_earnings_summary sama dengan 20261101180000 (match_call
-- dipisah, batas Asia/Jakarta, guard anti-IDOR) KECUALI v_withdrawable.
--
-- ⚠️ PERINGATAN ZONA WAKTU (ditambahkan 2026-11-02):
-- Baris `v_day_start := date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta')`
-- di bawah SALAH. `date_trunc` mengembalikan timestamp TANPA zona, yang lalu
-- dibandingkan dengan kolom `timestamptz` → Postgres menafsirkannya sebagai
-- UTC, jadi baris 23:29 UTC (06:29 WIB hari berikutnya) TIDAK terhitung.
-- Pola benar (dipakai 20261102230000):
--   (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp AT TIME ZONE 'Asia/Jakarta')
-- Jangan menyalin pola `date_trunc(...)` dari file ini.
-- ============================================================

-- menyentuh: get_earnings_summary

-- ── 1. spend_yukcoin — authenticated tidak boleh memanggil ─────────────
REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM authenticated;

-- ── 2. get_earnings_summary — withdrawable = bucket earned saja ────────
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
    -- ── Saldo yang bisa ditarik = saldo bersih bucket `earned` ──
    -- 2026-11-02: HANYA earned — request_withdraw menolak bonus, jadi
    -- total semua bucket menggelembungkan angka di layar Saldo.
    SELECT COALESCE(SUM(amount), 0) INTO v_withdrawable
      FROM public.coin_ledger
     WHERE user_id = p_user_id
       AND bucket = 'earned';
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
