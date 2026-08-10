-- ChatYuk Points System v1
-- Migration: profiles columns + point_events + app_settings + RPC functions

-- 1. New columns on profiles
alter table public.profiles
  add column if not exists points int not null default 50,
  add column if not exists one_time_actions jsonb not null default '{}',
  add column if not exists room_reads_today int not null default 0;

-- 2. Points enabled flag on app_settings
alter table public.app_settings
  add column if not exists points_enabled boolean not null default true;

-- 3. Analytics tracking table
create table if not exists public.point_events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade,
  event text not null,
  amount int not null default 0,
  metadata jsonb default '{}',
  created_at timestamptz not null default now()
);
create index if not exists idx_point_events_user on public.point_events(user_id, created_at);
create index if not exists idx_point_events_event on public.point_events(event, created_at);

-- 4. RPC: daily login bonus
create or replace function public.daily_login_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare r int;
begin
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
revoke execute on function public.daily_login_bonus() from public, anon;
grant execute on function public.daily_login_bonus() to authenticated, service_role;

-- 5. RPC: deduct chat point (atomic, called BEFORE message insert)
create or replace function public.deduct_chat_point(msg_type text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  points_enabled_val boolean;
  cost int;
  remaining int;
begin
  select points_enabled into points_enabled_val
    from app_settings where id = 'global';
  if points_enabled_val is false then
    select points from profiles where id = auth.uid() into remaining;
    return coalesce(remaining, 0);
  end if;

  cost := case msg_type
    when 'image' then 3
    when 'view_once' then 3
    when 'view_once_expired' then 0
    else 1
  end;

  update profiles
  set points = points - cost
  where id = auth.uid()
  returning points into remaining;

  if remaining < 0 then
    update profiles set points = points + cost where id = auth.uid();
    raise exception 'Not enough points';
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));

  return remaining;
end;
$$;
grant execute on function public.deduct_chat_point(text) to authenticated, service_role;

-- 6. RPC: room read bonus (5x/day)
create or replace function public.room_read_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare r int;
begin
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

-- 7. RPC: one-time action bonus (whitelisted keys)
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  valid_actions text[];
  r int;
begin
  valid_actions := array['registered','rated_app','completed_profile',
    'shared_app','first_photo','first_room_chat',
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

-- 8. RPC: register bonus
create or replace function public.register_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.one_time_bonus('registered', 100);
end;
$$;
grant execute on function public.register_bonus() to authenticated, service_role;

-- 9. RPC: admin stats (admin only)
create or replace function public.admin_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total_users', (select count(*) from profiles),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'),
    'registered_users', (select count(*) from profiles where is_registered = true),
    'anonymous_users', (select count(*) from profiles where is_registered = false),
    'messages_today',
      (select count(*) from private_messages where created_at >= current_date at time zone 'Asia/Jakarta') +
      (select count(*) from messages where created_at >= current_date at time zone 'Asia/Jakarta'),
    'rooms_active', (select count(distinct room_id) from room_presence where left_at is null),
    'avg_points', (select round(avg(points)) from profiles),
    'total_points', (select sum(points) from profiles),
    'top_earners', (select coalesce(jsonb_agg(
      jsonb_build_object('nickname', nickname, 'points', points, 'uid', id)
      order by points desc), '[]'::jsonb) from (select id, nickname, points from profiles order by points desc limit 10) t),
    'stuck_users', (select count(*) from profiles
      where points = 0 and last_seen >= (now() - interval '7 days')),
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object('reported_id', reported_id, 'report_count', c)
      order by c desc), '[]'::jsonb)
      from (select reported_id, count(*) as c from reports
            group by reported_id order by c desc limit 20) sub),
    'points_enabled', (select points_enabled from app_settings where id = 'global')
  ) into result;

  return result;
end;
$$;
grant execute on function public.admin_stats() to authenticated, service_role;

-- 10. RPC: admin mass bonus (admin only)
create or replace function public.admin_mass_bonus(bonus int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare affected int;
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update profiles set points = points + bonus where is_registered = true;
  get diagnostics affected = row_count;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_mass_bonus', bonus,
            jsonb_build_object('affected_users', affected));

  return jsonb_build_object('affected', affected, 'bonus', bonus);
end;
$$;
grant execute on function public.admin_mass_bonus(int) to authenticated, service_role;

-- 11. RPC: admin reset all points (admin only)
create or replace function public.admin_reset_points()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare affected int;
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update profiles set points = 50;
  get diagnostics affected = row_count;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_reset_all', 0,
            jsonb_build_object('affected_users', affected));

  return affected;
end;
$$;
grant execute on function public.admin_reset_points() to authenticated, service_role;

-- 12. RPC: admin toggle points system (admin only)
create or replace function public.admin_toggle_points(enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update app_settings
  set points_enabled = enabled, updated_at = now()
  where id = 'global';

  return enabled;
end;
$$;
grant execute on function public.admin_toggle_points(boolean) to authenticated, service_role;
