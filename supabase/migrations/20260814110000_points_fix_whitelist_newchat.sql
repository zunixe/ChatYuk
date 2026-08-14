-- ============================================================
-- ChatYuk Points: fix A + C
-- A: whitelist 'invited_friend' + RPC new_chat_bonus (harian ber-limit)
-- C: RPC get_points_enabled (dipanggil client, hilang dari migration)
-- ============================================================

-- ── C. RPC get_points_enabled ──
-- Dipanggil points_service.dart. create or replace: aman kalau sudah ada.
create or replace function public.get_points_enabled()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v boolean;
begin
  select points_enabled into v from app_settings where id = 'global';
  return coalesce(v, true);
end;
$$;
grant execute on function public.get_points_enabled() to authenticated, anon, service_role;

-- ── A1. Kolom counter chat orang baru harian ──
alter table public.profiles
  add column if not exists new_chats_today int not null default 0;

-- ── A2. Whitelist: tambah 'invited_friend' (+30 dari tombol share profil) ──
-- Beda channel beda nilai: invited_friend (+30, profil) vs shared_app (+10, dialog)
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

-- ── A3. RPC new_chat_bonus: +5 chat orang baru, maks 3×/hari ──
-- Guard 1: pasangan (user, other_uid) hanya sekali seumur hidup (anti-farming)
-- Guard 2: new_chats_today < 3 (limit harian, direset di daily_login_bonus)
create index if not exists idx_point_events_new_chat
  on public.point_events (user_id, event, ((metadata->>'other_uid')));

create or replace function public.new_chat_bonus(other_uid uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  points_enabled_val boolean;
  r int;
begin
  select points_enabled into points_enabled_val
    from app_settings where id = 'global';
  if points_enabled_val is false then
    select points from profiles where id = auth.uid() into r;
    return coalesce(r, 0);
  end if;

  -- Guard 1: sudah pernah dapat bonus untuk orang ini
  if exists (
    select 1 from point_events
    where user_id = auth.uid()
      and event = 'new_chat'
      and metadata->>'other_uid' = other_uid::text
  ) then
    select points from profiles where id = auth.uid() into r;
    return coalesce(r, 0);
  end if;

  -- Guard 2: limit harian 3×
  update profiles
  set points = points + 5,
      new_chats_today = new_chats_today + 1
  where id = auth.uid() and new_chats_today < 3
  returning points into r;

  if found then
    insert into point_events (user_id, event, amount, metadata)
      values (auth.uid(), 'new_chat', 5, jsonb_build_object('other_uid', other_uid));
    return r;
  end if;

  select points from profiles where id = auth.uid() into r;
  return coalesce(r, 0);
end;
$$;
grant execute on function public.new_chat_bonus(uuid) to authenticated, service_role;
