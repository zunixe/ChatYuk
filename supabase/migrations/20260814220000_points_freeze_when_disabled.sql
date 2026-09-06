-- ============================================================
-- ChatYuk Points: FREEZE total saat sistem poin OFF.
--
-- Saat app_settings.points_enabled = false, SEMUA aktivitas poin
-- membeku: tidak ada yang menambah maupun mengurangi poin.
--
-- Client sudah nge-guard (PointsProvider._enabled), tapi ini
-- enforcement di server (defense-in-depth) supaya poin benar-benar
-- freeze walau ada jalur lain / client dimodifikasi.
--
-- RPC yang sebelumnya BELUM cek points_enabled, ditambahkan guard:
--   - daily_login_bonus   (+25)
--   - room_read_bonus     (+2)
--   - one_time_bonus      (bonus achievement)  → register_bonus ikut
--   - send_coins          (transfer antar user)
--   - claim_weekly_quest  (+50)
-- Pola: kalau OFF → return saldo saat ini, tanpa perubahan apa pun.
-- ============================================================

-- ── daily_login_bonus: freeze saat OFF ──
drop function if exists public.daily_login_bonus();
create function public.daily_login_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r int;
  points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    select points from profiles where id = auth.uid() into r;
    return coalesce(r, 0);
  end if;

  if exists (select 1 from profiles
             where id = auth.uid()
             and login_at >= current_date at time zone 'Asia/Jakarta')
  then
    select points from profiles where id = auth.uid() into r;
    return r;
  end if;

  update profiles set
    points = points + 25,
    login_at = now(),
    room_reads_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min'
    ]
  where id = auth.uid()
  returning points into r;

  insert into point_events (user_id, event, amount)
    values (auth.uid(), 'daily_login', 25);

  return r;
end;
$$;
grant execute on function public.daily_login_bonus() to authenticated, service_role;

-- ── room_read_bonus: freeze saat OFF ──
drop function if exists public.room_read_bonus();
create function public.room_read_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r int;
  points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    select points from profiles where id = auth.uid() into r;
    return coalesce(r, 0);
  end if;

  update profiles
  set points = points + 2, room_reads_today = room_reads_today + 1
  where id = auth.uid() and room_reads_today < 5
  returning points into r;

  if found then
    insert into point_events (user_id, event, amount)
      values (auth.uid(), 'room_read', 2);
  end if;

  return coalesce(r, (select points from profiles where id = auth.uid()));
end;
$$;
grant execute on function public.room_read_bonus() to authenticated, service_role;

-- ── one_time_bonus: freeze saat OFF (register_bonus ikut, karena wrapper) ──
drop function if exists public.one_time_bonus(text, int);
create function public.one_time_bonus(action_key text, bonus int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  valid_actions text[];
  r int;
  points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    select points from profiles where id = auth.uid() into r;
    return coalesce(r, 0);
  end if;

  valid_actions := array['registered','rated_app','completed_profile',
    'shared_app','invited_friend','first_photo','first_room_chat',
    'online_5min','online_30min','online_60min','online_120min'];

  if not (action_key = any(valid_actions)) then
    raise exception 'Invalid action key: %', action_key;
  end if;

  if exists (select 1 from profiles
             where id = auth.uid()
             and one_time_actions->>action_key = 'true')
  then
    select points from profiles where id = auth.uid() into r;
    return r;
  end if;

  update profiles
  set points = points + bonus,
      one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
  where id = auth.uid()
  returning points into r;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'bonus', bonus, jsonb_build_object('action', action_key));

  return r;
end;
$$;
grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;

-- ── send_coins: freeze transfer saat OFF ──
create or replace function public.send_coins(
  p_chat_id text,
  p_receiver_id uuid,
  p_amount int
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  am_registered boolean;
  remaining int;
  my_name text;
  my_gender text;
  points_on boolean;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  -- Sistem poin OFF → transfer dibekukan (tidak ada koin berpindah)
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    raise exception 'Points system disabled';
  end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then
    raise exception 'Invalid amount';
  end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  -- pengirim wajib terdaftar
  select is_registered, nickname, gender
    into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then
    raise exception 'Sender must be registered';
  end if;

  -- keduanya peserta chat
  if not exists (
    select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id
      and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)
  ) then
    raise exception 'Not a chat participant';
  end if;

  -- tidak saling blokir
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)
  ) then
    raise exception 'Blocked';
  end if;

  -- saldo cukup
  select points into remaining from public.profiles where id = uid;
  if coalesce(remaining, 0) < p_amount then
    raise exception 'Not enough points';
  end if;

  -- transfer atomik
  update public.profiles set points = points - p_amount where id = uid
    returning points into remaining;
  update public.profiles set points = points + p_amount where id = p_receiver_id;

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', p_amount);

  -- pesan bukti transfer (nominal disimpan di text)
  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0));
end;
$$;
revoke execute on function public.send_coins(text, uuid, int) from public, anon;
grant execute on function public.send_coins(text, uuid, int) to authenticated;

-- ── claim_weekly_quest: freeze klaim saat OFF ──
create or replace function public.claim_weekly_quest(quest_key text, tz_offset_minutes int default 0)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  wk_start timestamptz;
  wk text;
  progress int;
  target int;
  r int;
  points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    select points from profiles where id = auth.uid() into r;
    return jsonb_build_object('points', coalesce(r,0), 'claimed', false);
  end if;

  if quest_key not in ('w_login','w_social','w_active') then
    raise exception 'Invalid quest key: %', quest_key;
  end if;

  wk_start := public.week_start_utc(tz_offset_minutes);
  wk := public.week_label(tz_offset_minutes);

  -- Sudah diklaim minggu ini → idempotent
  if exists (select 1 from point_events where user_id = auth.uid()
    and event = 'weekly_quest' and metadata->>'key' = quest_key and metadata->>'week' = wk) then
    select points from profiles where id = auth.uid() into r;
    return jsonb_build_object('points', coalesce(r,0), 'claimed', false);
  end if;

  -- Hitung progress sesuai jenis misi
  if quest_key = 'w_login' then
    select count(distinct (created_at + make_interval(mins => tz_offset_minutes))::date)
      into progress from point_events
      where user_id = auth.uid() and event = 'daily_login' and created_at >= wk_start;
    target := 5;
  elsif quest_key = 'w_social' then
    select count(*) into progress from point_events
      where user_id = auth.uid() and event = 'new_chat' and created_at >= wk_start;
    target := 10;
  else
    select count(*) into progress from point_events
      where user_id = auth.uid() and event = 'deduct' and created_at >= wk_start;
    target := 100;
  end if;

  if progress < target then
    raise exception 'Quest not completed: % (%/%)', quest_key, progress, target;
  end if;

  update profiles set points = points + 50 where id = auth.uid()
    returning points into r;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'weekly_quest', 50,
            jsonb_build_object('key', quest_key, 'week', wk));

  return jsonb_build_object('points', r, 'claimed', true);
end;
$$;
revoke execute on function public.claim_weekly_quest(text, int) from public, anon;
grant execute on function public.claim_weekly_quest(text, int) to authenticated, service_role;

-- Re-grant (fungsi di-drop & recreate di atas, grant lama ikut hilang)
grant execute on function public.daily_login_bonus() to authenticated, service_role;
grant execute on function public.room_read_bonus() to authenticated, service_role;
grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;
grant execute on function public.send_coins(text, uuid, int) to authenticated, service_role;
grant execute on function public.claim_weekly_quest(text, int) to authenticated, service_role;
