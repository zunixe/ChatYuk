-- ============================================================
-- 160000 — Misi nyonya: progres = saldo earned (withdrawable) + min WD 2000
-- ============================================================
-- menyentuh: get_user_missions
--
-- Latar lanjutan dari 150000: progres nyonya_1000 memakai v_total
-- (SUM amount>0 SEMUA bucket = kumulatif seumur hidup) → female lama
-- langsung is_completed → tombol "Klaim +100" walau saldo yang bisa
-- ditarik (bucket earned net) masih jauh di bawah target.
-- Semantik misi "kumpulkan 1000 koin" = koin yang BENAR-BENAR dipegang
-- dan bisa ditarik (arah minimal withdrawal) → progress = saldo
-- bucket 'earned' NET (definisi sama dengan request_withdraw v_earned).
-- Belanja/withdraw menurunkan progres — misi = tahan koin, bukan
-- sekadar pernah memperoleh. v_total TETAP untuk unlock harian @1200.
--
-- Bonus: naikkan withdraw_min_coins 1500 → 2000 (keputusan produk).
-- ============================================================

create or replace function public.get_user_missions(p_user_id uuid, p_period_date date default null::date)
returns jsonb
language plpgsql
security definer
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

    -- Saldo bucket `earned` NET = koin yang benar-benar dipegang dan bisa
    -- ditarik (rumus sama dengan v_earned di request_withdraw).
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
               -- Misi 'coins' (nyonya_1000): progres = saldo earned net
               -- (withdrawable), bukan kumulatif seumur hidup.
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

-- Minimum withdrawal: 1500 → 2000 koin (keputusan produk — tombol
-- withdraw di app non-aktif di bawah angka ini; gate server tetap
-- memakai setting yang sama via get_withdraw_config/request_withdraw).
UPDATE public.app_settings
   SET withdraw_min_coins = 2000
 WHERE id = 'global' AND coalesce(withdraw_min_coins, 0) < 2000;
