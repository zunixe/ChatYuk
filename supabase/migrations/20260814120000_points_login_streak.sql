-- ============================================================
-- ChatYuk Points: fix D — Login Streak
-- Rewrite daily_login_bonus: bonus bertingkat berdasarkan hari
-- berturut-turut. Return jsonb {points, streak, bonus} supaya client
-- bisa tampilkan toast streak.
-- CATATAN: migration ini HARUS setelah 20260814110000 (yang menambah
-- kolom new_chats_today) karena fungsi ini me-reset kolom tersebut.
-- ============================================================

alter table public.profiles
  add column if not exists login_streak int not null default 0,
  add column if not exists last_login_date date;

-- Backfill: user yang login hari ini dianggap streak 1
update public.profiles
set login_streak = 1,
    last_login_date = (login_at at time zone 'Asia/Jakarta')::date
where last_login_date is null
  and login_at >= (current_date at time zone 'Asia/Jakarta');

-- Bonus bertingkat: 1→25, 2→30, 3→35, 4→40, 5→45, 6→50, 7→100 (siklus ulang)
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

-- Return type berubah int → jsonb, jadi fungsi lama harus di-drop dulu
drop function if exists public.daily_login_bonus();

create function public.daily_login_bonus()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  today date;
  last_date date;
  cur_points int;
  cur_streak int;
  new_streak int;
  bonus int;
  r int;
begin
  today := (now() at time zone 'Asia/Jakarta')::date;

  select last_login_date, points, login_streak
    into last_date, cur_points, cur_streak
    from profiles where id = auth.uid();

  -- Sudah klaim hari ini → idempotent, tidak menambah poin
  if last_date is not null and last_date >= today then
    return jsonb_build_object(
      'points', coalesce(cur_points, 0),
      'streak', coalesce(cur_streak, 0),
      'bonus', 0
    );
  end if;

  -- Hitung streak baru
  if last_date is not null and last_date = today - 1 then
    new_streak := coalesce(cur_streak, 0) + 1;
    -- Setelah hari ke-7 (bonus mingguan), siklus ulang ke 1
    if new_streak > 7 then
      new_streak := 1;
    end if;
  else
    new_streak := 1; -- pertama kali atau streak putus
  end if;

  bonus := public.streak_bonus_amount(new_streak);

  update profiles set
    points = points + bonus,
    login_streak = new_streak,
    last_login_date = today,
    login_at = now(),
    room_reads_today = 0,
    new_chats_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min'
    ]
  where id = auth.uid()
  returning points into r;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'daily_login', bonus,
            jsonb_build_object('streak', new_streak));

  return jsonb_build_object('points', r, 'streak', new_streak, 'bonus', bonus);
end;
$$;
revoke execute on function public.daily_login_bonus() from public, anon;
grant execute on function public.daily_login_bonus() to authenticated, service_role;
