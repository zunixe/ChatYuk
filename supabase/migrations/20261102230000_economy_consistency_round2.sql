-- ============================================================
-- 20261102230000_economy_consistency_round2.sql
-- Lanjutan audit ekosistem koin 2026-11-02.
--
-- 1. `get_earnings_summary.withdrawable` menjumlah SEMUA bucket, padahal
--    `request_withdraw` (sejak 20261101190000) hanya menerima bucket
--    `earned`. Layar Saldo memakai angka itu sebagai headline → bisa
--    melebihkan yang benar-benar bisa ditarik.
--    → `withdrawable` kini hanya bucket `earned`; `total_balance` baru
--      ditambahkan supaya UI tetap bisa menampilkan total.
-- 2. `get_user_missions` SECURITY DEFINER tanpa `SET search_path`
--    (sisa item yang belum tuntas).
-- 3. `claim_mission_reward` tidak memeriksa `missions.gender` — misi
--    female-only (nyonya_1000) difilter hanya di UI, bisa diklaim male
--    lewat RPC langsung.
-- 4. `streak_bonus_amount` tanpa REVOKE → anon bisa memanggil.
-- 5. `spend_yukcoin` masih ter-grant ke authenticated dengan semantik
--    gift lama (menerima bucket bonus) — tidak ada pemanggil client,
--    permukaan mati yang menyesatkan.
-- ============================================================

-- ── 1. get_earnings_summary: withdrawable = earned saja ────────────────
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

    -- 2026-11-02: yang bisa DITARIK = bucket `earned` saja (sama dengan
    -- validasi request_withdraw). `total_balance` = semua bucket, untuk
    -- informasi — jangan tertukar.
    SELECT COALESCE(SUM(amount) FILTER (WHERE bucket = 'earned'), 0)
      INTO v_withdrawable
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

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
$$;

REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;

-- ── 2. get_user_missions: tambah SET search_path ───────────────────────
-- menyentuh: get_user_missions
CREATE OR REPLACE FUNCTION public.get_user_missions(p_user_id uuid, p_period_date date default null::date)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
    result jsonb;
    v_period date;
    v_total bigint;
    v_earned_bal bigint;
    v_streak int;
    v_last_login date;
    v_gender text;
BEGIN
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    v_period := COALESCE(p_period_date, CURRENT_DATE);

    SELECT COALESCE(SUM(amount), 0) INTO v_total
      FROM public.coin_ledger
     WHERE user_id = p_user_id AND amount > 0;

    SELECT COALESCE(SUM(amount), 0) INTO v_earned_bal
      FROM public.coin_ledger
     WHERE user_id = p_user_id AND bucket = 'earned';

    SELECT login_streak, last_login_date, gender
      INTO v_streak, v_last_login, v_gender
      FROM public.profiles
     WHERE id = p_user_id;

    WITH main_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order,
               CASE WHEN m.target_unit = 'coins'
                    THEN GREATEST(0, LEAST(v_earned_bal, m.target_value))::int
                    ELSE COALESCE(um.progress, 0) END AS progress,
               CASE WHEN m.target_unit = 'coins'
                    THEN (v_earned_bal >= m.target_value)
                    ELSE COALESCE(um.is_completed, false) END AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date IS NULL
        WHERE NOT m.is_daily
          AND (m.gender = 'all' OR m.gender = COALESCE(v_gender, 'all'))
    ),
    daily_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order, m.unlock_condition, m.schedule_start, m.schedule_end,
               COALESCE(um.progress, 0) AS progress,
               COALESCE(um.is_completed, false) AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at,
               (v_total >= 1200) AS unlocked_by_total
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date = v_period
        WHERE m.is_daily
          AND (m.gender = 'all' OR m.gender = COALESCE(v_gender, 'all'))
    )
    SELECT jsonb_build_object(
        'main', (SELECT jsonb_agg(row_to_json(m) ORDER BY m.display_order) FROM main_missions m),
        'daily', (SELECT jsonb_agg(row_to_json(dm) ORDER BY dm.display_order) FROM daily_missions dm),
        'total_coins', v_total,
        'login_streak', COALESCE(v_streak, 0),
        'last_login_date', v_last_login,
        'gender', v_gender
    ) INTO result;

    RETURN result;
END;
$function$;

-- ── 3. claim_mission_reward: tegakkan gender misi ──────────────────────
-- menyentuh: claim_mission_reward
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
    v_reward_bucket := CASE WHEN v_gender = 'female' THEN 'earned' ELSE 'bonus' END;

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
$$;

REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;

-- ── 4. streak_bonus_amount: cabut akses anon ───────────────────────────
-- SAFE: fungsi immutable (hanya membaca tier), tidak ada konsumen client.
-- Terdampak: tidak ada — mencegah anon membaca tier bonus.
REVOKE EXECUTE ON FUNCTION public.streak_bonus_amount(integer) FROM public, anon; -- SAFE: mencegah anon memanggil fungsi tier bonus. Terdampak: tidak ada (hanya dipakai internal daily_login_bonus).

-- ── 5. spend_yukcoin: cabut permukaan mati ─────────────────────────────
-- SAFE: tidak ada pemanggil client (wiring-nya sudah dihapus 2026-11-01).
-- Semantik gift lama masih menerima bucket `bonus` → menyesatkan.
-- Jalur match memakai `_spend_yukcoin_core` (service_role), tidak terpengaruh.
-- Terdampak: tidak ada — tidak ada UI yang memanggil.
REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM authenticated; -- SAFE: permukaan mati; tidak ada pemanggil client. Terdampak: tidak ada.
