-- ============================================================
-- 140000 — Misi per-gender: nyonya_1000 hanya female
-- ============================================================
-- Latar: halaman Bonus male menampilkan "Misi Nyonya 0/1000" — misi
-- milestone PENGUMPULAN koin (target 1000 koin kumulatif) yang masuk
-- akal untuk female (penghasil), bukan male (pemakai). Keluhan user:
-- "misi nyonya itu tugas pemula 0/1000 untuk yang perempuan".
--
-- Solusi: kolom `gender` di tabel missions ('all' default) — extensible
-- untuk misi gender-specific berikutnya; get_user_missions memfilter
-- berdasarkan gender user. Judul dirapikan (suffix "0/1000" dobel dengan
-- label progres UI dihapus).
-- ============================================================

alter table public.missions
  add column if not exists gender text not null default 'all';

update public.missions set gender = 'female', title = 'Misi Nyonya'
 where mission_key = 'nyonya_1000';

-- get_user_missions: hanya misi 'all' atau yang cocok gender user.
create or replace function public.get_user_missions(p_user_id uuid, p_period_date date default null::date)
returns jsonb
language plpgsql
security definer
as $function$
DECLARE
    result jsonb;
    v_period date;
    v_total bigint;
    v_streak int;
    v_last_login date;
    v_gender text;
BEGIN
    -- GUARD (audit 2026-10-31): user hanya boleh membaca misi SENDIRI.
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    v_period := COALESCE(p_period_date, CURRENT_DATE);

    -- Total koin KUMULATIF seumur hidup = jumlah semua kredit (bukan saldo
    -- bersih) — unlock misi harian @1200 tidak turun saat user belanja.
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM public.coin_ledger
    WHERE user_id = p_user_id AND amount > 0;

    SELECT login_streak, last_login_date, gender
      INTO v_streak, v_last_login, v_gender
    FROM public.profiles
    WHERE id = p_user_id;

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
