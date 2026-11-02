-- ══════════════════════════════════════════════════════════════════════
-- Fix get_earnings_summary: "Penghasilan" hanya menghitung UANG MASUK.
--
-- Masalah: entri negatif (withdraw, spend, cleanup reset bonus) ikut
-- dijumlahkan → "Minggu Ini" / "Hari Ini" bisa MINUS, dan rincian
-- "Lainnya" negatif. Untuk layar Saldo itu menyesatkan.
--
-- Aturan baru:
--   • total/weekly/today_earnings = SUM hanya entri POSITIF (credit).
--   • breakdown = hanya entri positing, dikategorikan per jenis.
--   • Entri non-penghasilan dikecualikan: withdraw, spend_chat, gift_sent,
--     *_cleanup, female_bonus_reset, test_*.
--   • Artefak uji (ref_id 't' / 'test-income' / 'cleanup_*') dikecualikan
--     dari laporan (tetap ada di ledger untuk audit).
--   • `withdrawable` TETAP = saldo bersih (total semua bucket).
-- ══════════════════════════════════════════════════════════════════════

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
    -- ── Penghasilan: HANYA tipe income yang benar-benar uang masuk ──
    -- (bonus pendaftaran/welcome/daily login BUKAN penghasilan; female
    --  bahkan tidak boleh punya bonus sama sekali).
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= date_trunc('week', now())), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= current_date), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'gift_recv'), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'mission_reward'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type IN ('call_audio_income','call_video_income',
                           'private_call_income','match_call_income',
                           'photo_unlock_income')), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type NOT IN ('gift_recv','mission_reward',
                               'call_audio_income','call_video_income',
                               'private_call_income','match_call_income',
                               'photo_unlock_income')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission, v_call, v_other
    FROM public.coin_ledger
    WHERE user_id = p_user_id
      AND amount > 0
      AND type IN (
            -- hadiah dari user lain
            'gift_recv',
            -- reward misi
            'mission_reward',
            -- penghasilan panggilan (dikreditkan ke penerima)
            'call_audio_income','call_video_income',
            'private_call_income','match_call_income',
            -- bagian pemilik foto saat fotonya dibuka
            'photo_unlock_income'
      )
      -- Kecualikan artefak uji (tetap tersimpan di ledger untuk audit).
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

REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;
