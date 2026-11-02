-- Fix migrasi misi: samakan dengan skema coin_ledger asli + perbaiki UPSERT
-- Bug yang diperbaiki:
--   1. get_user_missions memakai kolom `kind` (tidak ada) → coin_ledger pakai `type`/`bucket`
--   2. claim_mission_reward UPDATE profiles.points manual → DOBEL (trigger trg_coin_ledger_balance sudah auto)
--   3. update_mission_progress tidak pernah INSERT baris baru (NOT FOUND setelah SELECT, bukan UPDATE)
--   4. UNIQUE(user_id, mission_id, period_date) tidak match NULL → ON CONFLICT gagal

-- ── 1. Unique index yang match NULL (COALESCE ke sentinel) ──
ALTER TABLE public.user_missions
    DROP CONSTRAINT IF EXISTS user_missions_user_id_mission_id_period_date_key;

DROP INDEX IF EXISTS public.user_missions_unique;

CREATE UNIQUE INDEX user_missions_unique
    ON public.user_missions (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date));

-- ── 2. update_mission_progress: UPSERT yang benar ──
CREATE OR REPLACE FUNCTION public.update_mission_progress(
    p_user_id uuid,
    p_mission_key text,
    p_increment int DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mission record;
    v_period date;
    v_progress int;
    v_completed boolean;
BEGIN
    SELECT * INTO v_mission
    FROM public.missions
    WHERE mission_key = p_mission_key;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    -- Misi harian reset tiap hari; misi utama = seumur hidup (period_date NULL)
    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

    INSERT INTO public.user_missions
        (user_id, mission_id, progress, is_completed, completed_at, period_date)
    VALUES (
        p_user_id,
        v_mission.id,
        LEAST(p_increment, v_mission.target_value),
        p_increment >= v_mission.target_value,
        CASE WHEN p_increment >= v_mission.target_value THEN now() END,
        v_period
    )
    ON CONFLICT (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date)) DO UPDATE SET
        progress = LEAST(user_missions.progress + p_increment, v_mission.target_value),
        is_completed = (user_missions.progress + p_increment >= v_mission.target_value),
        completed_at = CASE
            WHEN user_missions.progress + p_increment >= v_mission.target_value
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

-- ── 3. claim_mission_reward: jangan UPDATE profiles manual (trigger yang urus) ──
CREATE OR REPLACE FUNCTION public.claim_mission_reward(
    p_user_id uuid,
    p_mission_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mission record;
    v_user_mission record;
    v_period date;
    v_new_points int;
BEGIN
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
      AND COALESCE(period_date, '1970-01-01'::date) = COALESCE(v_period, '1970-01-01'::date);

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_STARTED');
    END IF;

    IF NOT v_user_mission.is_completed THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
    END IF;

    IF v_user_mission.claimed THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;

    UPDATE public.user_missions
    SET claimed = true, claimed_at = now()
    WHERE id = v_user_mission.id;

    -- Trigger trg_coin_ledger_balance() OTOMATIS menambah profiles.points
    -- (bucket 'bonus' → bonus_balance; points selalu bertambah).
    INSERT INTO public.coin_ledger (user_id, bucket, type, amount, ref_id)
    VALUES (p_user_id, 'bonus', 'mission_reward', v_mission.reward_coins, p_mission_key);

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

-- ── 4. get_user_missions: pakai skema coin_ledger yang benar ──
CREATE OR REPLACE FUNCTION public.get_user_missions(
    p_user_id uuid,
    p_period_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result jsonb;
    v_period date;
    v_total bigint;
BEGIN
    v_period := COALESCE(p_period_date, CURRENT_DATE);

    -- Total koin seumur hidup (dipakai unlock misi harian @1200)
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM public.coin_ledger
    WHERE user_id = p_user_id;

    WITH main_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order,
               COALESCE(um.progress, 0) AS progress,
               COALESCE(um.is_completed, false) AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date IS NULL
        WHERE NOT m.is_daily
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
    )
    SELECT jsonb_build_object(
        'main', (SELECT jsonb_agg(row_to_json(m) ORDER BY m.display_order) FROM main_missions m),
        'daily', (SELECT jsonb_agg(row_to_json(dm) ORDER BY dm.display_order) FROM daily_missions dm),
        'total_coins', v_total
    ) INTO result;

    RETURN result;
END;
$$;

-- Grants (CREATE OR REPLACE mewarisi, tapi pastikan)
REVOKE EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_missions(uuid, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_missions(uuid, date) TO authenticated, service_role;
