-- Migration untuk misi gender points dan daily missions
-- Dibuat untuk implementasi misi gender points

-- ==================== 1. Buat tabel Missions (Data Master) ====================
CREATE TABLE IF NOT EXISTS public.missions (
    id bigserial PRIMARY KEY,
    mission_key text UNIQUE NOT NULL,
    title text NOT NULL,
    description text,
    category text NOT NULL CHECK (category IN ('duration', 'social', 'content', 'call', 'match', 'special', 'daily')),
    target_value int NOT NULL,
    target_unit text NOT NULL,  -- 'minutes', 'photos', 'users', 'calls', 'likes', 'posts', 'coins'
    reward_coins int NOT NULL DEFAULT 0,
    is_daily boolean NOT NULL DEFAULT false,
    is_locked boolean NOT NULL DEFAULT false,
    unlock_condition jsonb,  -- {'type': 'total_coins', 'value': 1200} atau lainnya
    schedule_start time,    -- untuk misi jam (19:00)
    schedule_end time,      -- untuk misi jam (23:00)
    display_order int DEFAULT 0,
    created_at timestamptz DEFAULT now()
);

-- RLS: biarkan user melihat semua missions
ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY;
CREATE POLICY missions_public ON public.missions -- SAFE: tabel BARU `missions` (master misi), read-only semua; tidak ada fitur lain terbawa
    FOR SELECT USING (true);

-- ==================== 2. Buat tabel UserMissions (Progress User) ====================
CREATE TABLE IF NOT EXISTS public.user_missions (
    id bigserial PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    mission_id bigint REFERENCES public.missions(id) ON DELETE CASCADE,
    progress int NOT NULL DEFAULT 0,
    is_completed boolean NOT NULL DEFAULT false,
    completed_at timestamptz,
    claimed boolean NOT NULL DEFAULT false,
    claimed_at timestamptz,
    period_date date,  -- untuk daily missions
    UNIQUE(user_id, mission_id, period_date)
);

ALTER TABLE public.user_missions ENABLE ROW LEVEL SECURITY;
-- User bisa lihat/update hanya missions mereka sendiri
CREATE POLICY user_missions_own ON public.user_missions -- SAFE: tabel BARU `user_missions` (progress misi), RLS own-only; tidak menyentuh tabel bersama
    FOR ALL USING (user_id = auth.uid());

-- ==================== 3. Insert Data Misi Utama ====================
INSERT INTO public.missions (
    mission_key, title, description, category, target_value, target_unit,
    reward_coins, is_daily, is_locked, display_order
) VALUES
    -- Misi Online/Durasi
    ('daily_online_minutes', 'Jam Menit Online', 
     'Total durasi online hari ini', 'duration', 60, 'minutes', 10,
     false, false, 1),
    ('call_minutes', 'Jam Menit Panggilan', 
     'Total durasi panggilan hari ini', 'duration', 30, 'minutes', 15,
     false, false, 2),
    ('daily_online_duration', 'Durasi Online Harian', 
     'Online minimal 60 menit/hari', 'duration', 60, 'minutes', 10,
     false, false, 12),

    -- Misi Konten
    ('upload_photos', 'Unggah 3 Foto', 
     'Unggah foto ke profil', 'content', 3, 'photos', 20,
     false, false, 4),
    ('create_posts', 'Buat Postingan', 
     'Buat 5 posting di timeline', 'content', 5, 'posts', 15,
     false, false, 11),

    -- Misi Match/Call
    ('match_calls', 'Panggilan Match', 
     'Lakukan 5 video match', 'match', 5, 'calls', 25,
     false, false, 6),
    ('private_calls', 'Panggilan Pribadi', 
     'Lakukan 3 panggilan 1:1', 'call', 3, 'calls', 20,
     false, false, 9),

    -- Misi Sosial
    ('message_various_users', 'Pesan ke Berbagai Pengguna', 
     'Kirim pesan ke 10 user berbeda', 'social', 10, 'users', 10,
     false, false, 5),
    ('add_friends_in_call', 'Tambah 3 Teman', 
     'Tambah 3 teman selama panggilan', 'social', 3, 'friends', 15,
     false, false, 7),
    ('reply_users', 'Membalas Pengguna', 
     'Balas 20 pesan pengguna', 'social', 20, 'replies', 10,
     false, false, 8),
    ('like_posts', 'Suka 3 Postingan', 
     'Suka 3 postingan orang lain', 'social', 3, 'likes', 5,
     false, false, 13),

    -- Misi Khusus
    ('nyonya_1000', 'Misi Nyonya 0/1000', 
     'Kumpulkan 1000 poin total', 'special', 1000, 'coins', 100,
     false, false, 3),

    -- Misi Harian (Locked - 0/1200)
    ('daily_match_calls', 'Panggilan Match Harian', 
     'Lakukan 3 match hari ini', 'match', 3, 'calls', 15,
     true, true, 1),
    ('daily_message_users', 'Pesan ke Pengguna', 
     'Kirim pesan ke 5 user berbeda', 'social', 5, 'users', 10,
     true, true, 2),
    ('daily_receive_gift', 'Terima Hadiah', 
     'Terima 1 hadiah dari user', 'social', 1, 'gifts', 20,
     true, true, 3),
    ('daily_private_call_duration', 'Durasi Panggilan Pribadi', 
     'Total 30 menit panggilan pribadi', 'call', 30, 'minutes', 15,
     true, true, 4),
    ('evening_online_call', '19:00-23:00 Online & Panggilan', 
     'Aktif 4 jam di jam malam', 'duration', 240, 'minutes', 25,
     true, true, 5),
    ('night_owl_online_call', '01:00-05:00 Online & Panggilan', 
     'Aktif 4 jam di jam dini hari', 'duration', 240, 'minutes', 25,
     true, true, 6);

-- ==================== 4. Buat RPC Functions ====================

-- RPC: update_mission_progress (atomik)
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
    v_progress int;
    v_completed boolean;
BEGIN
    -- Dapatkan data misi
    SELECT * INTO v_mission 
    FROM public.missions 
    WHERE mission_key = p_mission_key;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;
    
    -- Update progress (atomic)
    UPDATE public.user_missions
    SET progress = LEAST(progress + p_increment, v_mission.target_value),
        is_completed = (progress + p_increment >= v_mission.target_value),
        completed_at = CASE 
            WHEN progress + p_increment >= v_mission.target_value AND NOT is_completed 
            THEN now() 
            ELSE completed_at END
    WHERE user_id = p_user_id AND mission_id = v_mission.id
    RETURNING progress, is_completed INTO v_progress, v_completed;
    
    -- Jika baru selesai, buat record user_missions baru jika belum ada
    IF v_completed AND NOT FOUND THEN
        INSERT INTO public.user_missions (user_id, mission_id, progress, is_completed)
        VALUES (p_user_id, v_mission.id, v_mission.target_value, true)
        ON CONFLICT (user_id, mission_id) DO UPDATE SET
            progress = GREATEST(user_missions.progress, v_mission.target_value),
            is_completed = true,
            completed_at = GREATEST(user_missions.completed_at, now());
    END IF;
    
    RETURN jsonb_build_object(
        'progress', v_progress,
        'target', v_mission.target_value,
        'completed', v_completed,
        'reward_coins', v_mission.reward_coins
    );
END;
$$;

-- RPC: claim_mission_reward
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
    v_new_points int;
BEGIN
    -- Dapatkan data misi
    SELECT * INTO v_mission 
    FROM public.missions 
    WHERE mission_key = p_mission_key;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;
    
    -- Dapatkan progress user
    SELECT * INTO v_user_mission
    FROM public.user_missions
    WHERE user_id = p_user_id AND mission_id = v_mission.id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_STARTED');
    END IF;
    
    IF NOT v_user_mission.is_completed THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
    END IF;
    
    IF v_user_mission.claimed THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;
    
    -- Update claimed status
    UPDATE public.user_missions
    SET claimed = true, claimed_at = now()
    WHERE user_id = p_user_id AND mission_id = v_mission.id;
    
    -- Tambah poin
    UPDATE public.profiles
    SET points = points + v_mission.reward_coins
    WHERE id = p_user_id
    RETURNING points INTO v_new_points;
    
    -- Catat transaksi di coin_ledger
    INSERT INTO public.coin_ledger (user_id, kind, amount, ref_id)
    VALUES (p_user_id, 'mission_reward', v_mission.reward_coins, p_mission_key);
    
    RETURN jsonb_build_object(
        'success', true,
        'coins', v_mission.reward_coins,
        'total_points', v_new_points
    );
END;
$$;

-- RPC: get_user_missions (untuk UI)
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
BEGIN
    -- Select misi utama (non-daily)
    WITH main_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description, 
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order,
               um.progress, um.is_completed, um.claimed, um.completed_at
        FROM public.missions m
        LEFT JOIN public.user_missions um ON m.id = um.mission_id AND um.user_id = p_user_id
             AND (p_period_date IS NULL OR um.period_date = p_period_date)
        WHERE NOT m.is_daily
        ORDER BY m.display_order
    ),
    -- Select misi harian
    daily_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order, m.unlock_condition, m.schedule_start, m.schedule_end,
               um.progress, um.is_completed, um.claimed, um.completed_at,
               -- Cek apakah user sudah punya total 1200 poin untuk unlock
               (SELECT CASE WHEN p_user_id IN (
                   SELECT pm.user_id
                   FROM public.coin_ledger pm
                   WHERE pm.kind = 'welcome' AND pm.amount >= 1200
                   GROUP BY pm.user_id
               ) THEN true ELSE false END
               ) as unlocked_by_total
        FROM public.missions m
        LEFT JOIN public.user_missions um ON m.id = um.mission_id AND um.user_id = p_user_id
             AND (p_period_date IS NULL OR um.period_date = p_period_date)
        WHERE m.is_daily
        ORDER BY m.display_order
    )
    SELECT jsonb_build_object(
        'main', (SELECT jsonb_agg(row_to_json(m)) FROM main_missions m),
        'daily', (SELECT jsonb_agg(row_to_json(dm)) FROM daily_missions dm)
    ) INTO result;
    
    RETURN result;
END;
$$;

-- RPC: check_user_total_coins (untuk unlock misi)
CREATE OR REPLACE FUNCTION public.check_user_total_coins(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    total_coins int;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO total_coins
    FROM public.coin_ledger
    WHERE user_id = p_user_id;
    
    RETURN jsonb_build_object('total_coins', total_coins);
END;
$$;

-- Grant permissions
REVOKE EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_missions(uuid, date) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.check_user_total_coins(uuid) FROM public, anon;

GRANT EXECUTE ON FUNCTION public.update_mission_progress(uuid, text, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_mission_reward(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_missions(uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_user_total_coins(uuid) TO authenticated, service_role;

-- ✅ Migration selesai
COMMENT ON TABLE public.missions IS 'Tabel master untuk semua misi (utama dan harian)';
COMMENT ON TABLE public.user_missions IS 'Progress misi per user';
COMMENT ON COLUMN public.missions.is_locked IS 'Misi terkunci sampai syarat terpenuhi';
COMMENT ON COLUMN public.missions.unlock_condition IS 'JSON syarat unlock (total_coins, level, dll)';