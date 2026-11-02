-- ============================================================
-- 120000 — Daily Login Streak v2 (halaman Bonus ala Vava, male)
-- ============================================================
-- menyentuh: daily_login_bonus
--
-- Latar: daily_login_bonus di-stub no-op oleh 20261001010000
-- (disable free points). Halaman Bonus baru butuh sign-in rewards
-- 7 hari (grid ala Vava) → diaktifkan ulang dengan guard ekonomi:
--   • MALE only — female tidak pernah dapat tetesan gratis.
--   • Gate points_enabled (kill-switch ekonomi).
--   • Bucket 'bonus' (non-withdrawable) via ledger_credit — BUKAN
--     kolom profiles.points (ekonomi baru = coin_ledger).
--   • Idempotent per hari (last_login_date >= today → bonus 0).
--   • Tier kecil: 25/30/35/40/45/50/100 (streak_bonus_amount lama).
--
-- get_user_missions diperluas: field jsonb login_streak,
-- last_login_date, gender — client menggambar grid dari sini
-- (backward compatible, field tambahan).
-- ============================================================

-- ── 3. streak_bonus_amount — tier dikembalikan (dulu dinolkan oleh
--      20261001010000_disable_free_points demi kompat) ──────────────────
create or replace function public.streak_bonus_amount(streak int)
returns int
language sql
immutable
as $$
  select case streak
    when 1 then 25
    when 2 then 30
    when 3 then 35
    when 4 then 40
    when 5 then 45
    when 6 then 50
    else 100
  end;
$$;

-- ── 1. daily_login_bonus v2 ─────────────────────────────────────────
-- menyentuh: daily_login_bonus
create or replace function public.daily_login_bonus()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  today date;
  last_date date;
  cur_streak int;
  new_streak int;
  bonus int;
  v_gender text;
begin
  today := (now() at time zone 'Asia/Jakarta')::date;

  select last_login_date, login_streak, gender
    into last_date, cur_streak, v_gender
    from profiles where id = auth.uid();

  if v_gender is null then
    return jsonb_build_object('streak', 0, 'bonus', 0, 'total',
      public.yukcoin_total(auth.uid()));
  end if;

  -- Kill-switch ekonomi: points_enabled=false → tanpa kredit.
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('streak', coalesce(cur_streak, 0), 'bonus', 0,
      'total', public.yukcoin_total(auth.uid()));
  end if;

  -- Male only: female tidak pernah dapat tetesan koin gratis.
  if v_gender <> 'male' then
    return jsonb_build_object('streak', coalesce(cur_streak, 0), 'bonus', 0,
      'total', public.yukcoin_total(auth.uid()));
  end if;

  -- Sudah klaim hari ini → idempotent, tidak menambah koin.
  if last_date is not null and last_date >= today then
    return jsonb_build_object('streak', coalesce(cur_streak, 0), 'bonus', 0,
      'total', public.yukcoin_total(auth.uid()));
  end if;

  -- Streak: lanjut bila kemarin klaim; siklus ulang setelah hari ke-7.
  if last_date is not null and last_date = today - 1 then
    new_streak := coalesce(cur_streak, 0) + 1;
    if new_streak > 7 then
      new_streak := 1;
    end if;
  else
    new_streak := 1;
  end if;

  bonus := public.streak_bonus_amount(new_streak);

  update profiles set
    login_streak = new_streak,
    last_login_date = today,
    login_at = now(),
    room_reads_today = 0,
    new_chats_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min'
    ]
  where id = auth.uid();

  -- Bucket 'bonus' = non-withdrawable; wallet ikut via wallet_sync_points.
  perform public.ledger_credit(auth.uid(), 'bonus', 'daily_login', bonus,
    'daily_login', jsonb_build_object('streak', new_streak));

  return jsonb_build_object('streak', new_streak, 'bonus', bonus,
    'total', public.yukcoin_total(auth.uid()));
end;
$$;
revoke execute on function public.daily_login_bonus() from public, anon;
grant execute on function public.daily_login_bonus() to authenticated, service_role;

-- ── 2. get_user_missions — tambah data grid sign-in ─────────────────
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
        'total_coins', v_total,
        'login_streak', COALESCE(v_streak, 0),
        'last_login_date', v_last_login,
        'gender', v_gender
    ) INTO result;

    RETURN result;
END;
$function$;
