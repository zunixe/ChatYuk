-- Privacy controls for profile visibility, presence, stories and receipts.
-- Values: everyone | friends | except | nobody.

alter table public.profiles
  add column if not exists presence_visibility text not null default 'everyone',
  add column if not exists last_seen_visibility text not null default 'everyone',
  add column if not exists profile_photo_visibility text not null default 'everyone',
  add column if not exists about_visibility text not null default 'everyone',
  add column if not exists story_visibility text not null default 'everyone',
  add column if not exists about text not null default '',
  add column if not exists read_receipts_enabled boolean not null default true;

alter table public.profiles
  drop constraint if exists profiles_privacy_visibility_check;
alter table public.profiles
  add constraint profiles_privacy_visibility_check check (
    presence_visibility in ('everyone', 'friends', 'except', 'nobody')
    and last_seen_visibility in ('everyone', 'friends', 'except', 'nobody')
    and profile_photo_visibility in ('everyone', 'friends', 'except', 'nobody')
    and about_visibility in ('everyone', 'friends', 'except', 'nobody')
    and story_visibility in ('everyone', 'friends', 'except', 'nobody')
  );

create table if not exists public.profile_privacy_exclusions (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  excluded_uid uuid not null references public.profiles(id) on delete cascade,
  field text not null check (field in ('presence', 'last_seen', 'profile_photo', 'about', 'story')),
  created_at timestamptz not null default now(),
  primary key (owner_id, excluded_uid, field),
  check (owner_id <> excluded_uid)
);
create index if not exists idx_profile_privacy_exclusions_owner
  on public.profile_privacy_exclusions(owner_id, field);

alter table public.profile_privacy_exclusions enable row level security;
drop policy if exists profile_privacy_exclusions_own on public.profile_privacy_exclusions;
create policy profile_privacy_exclusions_own on public.profile_privacy_exclusions
  for all to authenticated using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create or replace function public.my_privacy_settings()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'presence', coalesce(presence_visibility, 'everyone'),
    'last_seen', coalesce(last_seen_visibility, 'everyone'),
    'profile_photo', coalesce(profile_photo_visibility, 'everyone'),
    'about', coalesce(about_visibility, 'everyone'),
    'story', coalesce(story_visibility, 'everyone'),
    'read_receipts', coalesce(read_receipts_enabled, true),
    'exclusions', coalesce((select jsonb_object_agg(field, ids) from (
      select field, jsonb_agg(excluded_uid) as ids
      from profile_privacy_exclusions
      where owner_id = auth.uid()
      group by field
    ) x), '{}'::jsonb)
  )
  from profiles where id = auth.uid();
$$;

create or replace function public.update_privacy_settings(
  p_presence text default null,
  p_last_seen text default null,
  p_profile_photo text default null,
  p_about text default null,
  p_story text default null,
  p_read_receipts boolean default null
)
returns jsonb language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_presence is not null and p_presence not in ('everyone','friends','except','nobody') then raise exception 'Invalid presence visibility'; end if;
  if p_last_seen is not null and p_last_seen not in ('everyone','friends','except','nobody') then raise exception 'Invalid last seen visibility'; end if;
  if p_profile_photo is not null and p_profile_photo not in ('everyone','friends','except','nobody') then raise exception 'Invalid profile photo visibility'; end if;
  if p_about is not null and p_about not in ('everyone','friends','except','nobody') then raise exception 'Invalid about visibility'; end if;
  if p_story is not null and p_story not in ('everyone','friends','except','nobody') then raise exception 'Invalid story visibility'; end if;
  update profiles set
    presence_visibility = coalesce(p_presence, presence_visibility),
    last_seen_visibility = coalesce(p_last_seen, last_seen_visibility),
    profile_photo_visibility = coalesce(p_profile_photo, profile_photo_visibility),
    about_visibility = coalesce(p_about, about_visibility),
    story_visibility = coalesce(p_story, story_visibility),
    read_receipts_enabled = coalesce(p_read_receipts, read_receipts_enabled)
  where id = auth.uid();
  return public.my_privacy_settings();
end;
$fn$;

create or replace function public.replace_privacy_exclusions(p_field text, p_uids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_field not in ('presence','last_seen','profile_photo','about','story') then raise exception 'Invalid privacy field'; end if;
  delete from profile_privacy_exclusions where owner_id = auth.uid() and field = p_field;
  insert into profile_privacy_exclusions(owner_id, excluded_uid, field)
  select auth.uid(), x, p_field from unnest(coalesce(p_uids, '{}'::uuid[])) x
  where x <> auth.uid()
  on conflict do nothing;
  return public.my_privacy_settings();
end;
$fn$;

-- Helper terpusat untuk RPC yang mengembalikan data profil/presence.
create or replace function public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_owner is null or p_viewer is null then false
    when p_owner = p_viewer then true
    when coalesce((select case p_field
      when 'presence' then presence_visibility
      when 'last_seen' then last_seen_visibility
      when 'profile_photo' then profile_photo_visibility
      when 'about' then about_visibility
      when 'story' then story_visibility
      else 'nobody' end from profiles where id = p_owner), 'nobody') = 'everyone' then true
    when coalesce((select case p_field
      when 'presence' then presence_visibility
      when 'last_seen' then last_seen_visibility
      when 'profile_photo' then profile_photo_visibility
      when 'about' then about_visibility
      when 'story' then story_visibility
      else 'nobody' end from profiles where id = p_owner), 'nobody') = 'nobody' then false
    when coalesce((select case p_field
      when 'presence' then presence_visibility
      when 'last_seen' then last_seen_visibility
      when 'profile_photo' then profile_photo_visibility
      when 'about' then about_visibility
      when 'story' then story_visibility
      else 'nobody' end from profiles where id = p_owner), 'nobody') = 'except'
      then not exists (select 1 from profile_privacy_exclusions e
                       where e.owner_id = p_owner and e.excluded_uid = p_viewer and e.field = p_field)
    when coalesce((select case p_field
      when 'presence' then presence_visibility
      when 'last_seen' then last_seen_visibility
      when 'profile_photo' then profile_photo_visibility
      when 'about' then about_visibility
      when 'story' then story_visibility
      else 'nobody' end from profiles where id = p_owner), 'nobody') = 'friends'
      then public._are_friends(p_viewer, p_owner)
    else false
  end;
$$;

create or replace function public.profile_public(p_user uuid default auth.uid())
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare r public.profiles%rowtype; me uuid := auth.uid(); result jsonb;
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;
  result := jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case when public.privacy_can_view(r.id, 'presence', me) then r.status else 'offline' end,
    'avatar', case when public.privacy_can_view(r.id, 'profile_photo', me) then r.avatar else '' end,
    'is_registered', r.is_registered,
    'login_at', r.login_at,
    'created_at', r.created_at,
    'last_seen', case when public.privacy_can_view(r.id, 'last_seen', me) then r.last_seen else null end,
    'about', case when public.privacy_can_view(r.id, 'about', me) then r.about else '' end,
    'hashtags', r.hashtags,
    'followers_count', r.followers_count,
    'following_count', r.following_count,
    'subscriber_count', r.subscriber_count,
    'subscription_price', r.subscription_price,
    'friends_count', r.friends_count
  );
  return result;
end;
$fn$;

revoke execute on function public.profile_public(uuid) from public, anon;
grant execute on function public.profile_public(uuid) to authenticated;

revoke execute on function public.my_privacy_settings() from public, anon;
grant execute on function public.my_privacy_settings() to authenticated;
revoke execute on function public.update_privacy_settings(text,text,text,text,text,boolean) from public, anon;
grant execute on function public.update_privacy_settings(text,text,text,text,text,boolean) to authenticated;
revoke execute on function public.replace_privacy_exclusions(text,uuid[]) from public, anon;
grant execute on function public.replace_privacy_exclusions(text,uuid[]) to authenticated;
revoke execute on function public.privacy_can_view(uuid,text,uuid) from public, anon;
grant execute on function public.privacy_can_view(uuid,text,uuid) to authenticated;

-- Enforce presence privacy in the online directory. Keep both overloads
-- because older clients call the one-argument RPC.
drop function if exists public.get_online_users(integer, text); -- SAFE: remove obsolete reversed-argument overload to prevent RPC ambiguity
create or replace function public.get_online_users(p_country text default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare rows jsonb; me uuid := auth.uid();
begin
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'nickname', s.nickname, 'gender', s.gender, 'age', s.age,
    'country', s.country, 'city', s.city,
    'status', case when public.privacy_can_view(s.id, 'presence', me) then s.status else 'offline' end,
    'avatar', case when public.privacy_can_view(s.id, 'profile_photo', me) then s.avatar else '' end,
    'is_registered', s.is_registered,
    'last_seen', case when public.privacy_can_view(s.id, 'last_seen', me) then s.last_seen else null end
  ) order by s.last_seen desc), '[]'::jsonb) into rows
  from (
    select id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen
    from public.profiles
    where id <> me and status in ('online','idle')
      and last_seen >= now() - interval '30 minutes'
      and (p_country is null or country = p_country)
      and public.privacy_can_view(id, 'presence', me)
    order by last_seen desc limit p_limit
  ) s;
  return rows;
end;
$fn$;

create or replace function public.get_online_users(p_limit int default 100)
returns jsonb language sql security definer set search_path = public as $$
  select public.get_online_users(null::text, p_limit);
$$;

-- Nearby is also an online directory and must obey the same presence rule.
create or replace function public.nearby_users(p_radius_km double precision default 10)
returns table(uid uuid, nickname text, gender text, age integer, country text, city text,
  status text, avatar text, is_registered boolean, last_seen timestamptz, distance_km double precision)
language plpgsql security definer set search_path = public as $fn$
declare me uuid := auth.uid(); my_lat double precision; my_lon double precision;
  radius_m double precision; v_excl uuid[];
begin
  if me is null then raise exception 'Not authenticated'; end if;
  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;
  select p.lat, p.lon into my_lat, my_lon from public.profiles p where p.id = me;
  if my_lat is null or my_lon is null then raise exception 'No location'; end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl from public.admin_excluded_uids() ae;
  return query
  select p.id, p.nickname, p.gender, p.age, p.country, p.city,
    p.status, case when public.privacy_can_view(p.id, 'profile_photo', me) then p.avatar else '' end,
    p.is_registered, case when public.privacy_can_view(p.id, 'last_seen', me) then p.last_seen else null end,
    (earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) / 1000.0)
  from public.profiles p
  where p.id <> me and p.lat is not null and p.lon is not null
    and coalesce(p.share_location, false) = true and p.status in ('online', 'idle')
    and p.last_seen >= now() - interval '30 minutes'
    and public.privacy_can_view(p.id, 'presence', me)
    and not (p.id = any(v_excl))
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by 12 asc limit 100;
end;
$fn$;

-- Read receipts: an owner who disabled receipts can still read messages, but
-- their last_read_at must not become visible as a blue check to the sender.
-- This wrapper is intentionally security-definer and only permits participants.
drop function if exists public.mark_chat_read(text, uuid); -- SAFE: replace existing read-receipt RPC with privacy-aware return contract
create or replace function public.mark_chat_read(p_chat_id text, p_uid uuid)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare me uuid := auth.uid(); current jsonb; now_text text := now()::text;
begin
  if me is null or p_uid <> me then raise exception 'Unauthorized'; end if;
  if not exists (select 1 from public.private_chats c
                 where c.chat_id = p_chat_id and me = any(c.participants)) then
    raise exception 'Unauthorized';
  end if;
  if not coalesce((select read_receipts_enabled from public.profiles where id = me), true) then
    return jsonb_build_object('ok', true, 'receipts', false);
  end if;
  select coalesce(last_read_at, '{}'::jsonb) into current
  from public.private_chats where chat_id = p_chat_id;
  update public.private_chats
  set last_read_at = jsonb_set(current, array[p_uid::text], to_jsonb(now_text), true),
      unread_counts = jsonb_set(coalesce(unread_counts, '{}'::jsonb), array[p_uid::text], '0'::jsonb, true)
  where chat_id = p_chat_id;
  return jsonb_build_object('ok', true, 'receipts', true);
end;
$fn$;

revoke execute on function public.get_online_users(text,int) from public, anon;
grant execute on function public.get_online_users(text,int) to authenticated;
revoke execute on function public.get_online_users(int) from public, anon;
grant execute on function public.get_online_users(int) to authenticated;
revoke execute on function public.nearby_users(double precision) from public, anon;
grant execute on function public.nearby_users(double precision) to authenticated;
revoke execute on function public.mark_chat_read(text,uuid) from public, anon;
grant execute on function public.mark_chat_read(text,uuid) to authenticated;

-- menyentuh: story_slides
-- menyentuh: nearby_users
create or replace function public.story_slides(p_author uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'image_path', s.image_path, 'text_overlay', s.text_overlay,
    'text_x', s.text_x, 'text_y', s.text_y, 'text_color', s.text_color,
    'text_size', s.text_size, 'text_scale', s.text_scale,
    'text_rotation', s.text_rotation, 'text_bg', s.text_bg,
    'visibility', s.visibility,
    'like_count', (select count(*) from public.story_likes l where l.story_id = s.id),
    'liked', exists (select 1 from public.story_likes l where l.story_id = s.id and l.user_id = auth.uid()),
    'created_at', s.created_at
  ) order by s.created_at asc), '[]'::jsonb) into result
  from public.stories s
  where s.author_id = p_author and s.expires_at > now()
    and public.privacy_can_view(s.author_id, 'story', auth.uid())
    and (
      s.author_id = auth.uid()
      or ((s.visibility = 'everyone')
        or (s.visibility = 'followers' and exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = s.author_id))
        or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))
      and not exists (select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id) or (b.blocker_id = s.author_id and b.blocked_id = auth.uid()))
    );
  return result;
end;
$fn$;
revoke execute on function public.story_slides(uuid) from public, anon;
grant execute on function public.story_slides(uuid) to authenticated;
