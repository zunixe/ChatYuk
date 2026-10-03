-- ============================================================
-- Privasi "Top Aktif" (leaderboard): kolom leaderboard_visibility + filter.
--
-- Tujuan: user bisa mengatur visibilitas muncul-di-Top-Aktif sama seperti
-- field privasi lain (everyone/everyone_except/friends/friends_except/
-- only/nobody). Default 'everyone' (perilaku lama tak berubah).
--
-- Field baru: 'leaderboard' (dipakai di profile_privacy_exclusions juga).
-- YANG DIUBAH (salin PERSIS dari live + tambahan):
--   1. profiles: +kolom leaderboard_visibility (default everyone).
--   2. CHECK profile_privacy_exclusions_field_check: +'leaderboard'.
--   3. update_privacy_settings: +param p_leaderboard (+ validasi + 'only').
--   4. my_privacy_settings: +'leaderboard'.
--   5. privacy_can_view: mapping field 'leaderboard' → leaderboard_visibility.
--   6. replace_privacy_exclusions: +'leaderboard' di whitelist field.
--   7. activity_leaderboard: filter privacy_can_view(id,'leaderboard',viewer)
--      di KEDUA CTE final (entries & me).
--
-- TIDAK ada aturan "mitra chat/anggota room" untuk leaderboard (keputusan:
-- Top Aktif patuh penuh ke visibility).
--
-- CARA APPLY: Management API (lihat APPLIED_VIA_API.md), 1 statement/request.
-- ============================================================

-- ── 1) Kolom ──
alter table public.profiles
  add column if not exists leaderboard_visibility text not null default 'everyone';

-- ── 2) CHECK exclusions: tambah 'leaderboard' ──
alter table public.profile_privacy_exclusions
  drop constraint if exists profile_privacy_exclusions_field_check;
alter table public.profile_privacy_exclusions
  add constraint profile_privacy_exclusions_field_check
  check (field = any (array['presence','last_seen','profile_photo','about','story','leaderboard']));

-- ── 3) update_privacy_settings ──
-- DROP versi 6-arg lama (tanpa p_leaderboard) supaya tak jadi OVERLOAD
-- ambigu (pemanggil 6-arg jadi "function is not unique").
drop function if exists public.update_privacy_settings(text, text, text, text, text, boolean);
create or replace function public.update_privacy_settings(
  p_presence text default null,
  p_last_seen text default null,
  p_profile_photo text default null,
  p_about text default null,
  p_story text default null,
  p_read_receipts boolean default null,
  p_leaderboard text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_allowed text[] := array['everyone','everyone_except','friends','friends_except','only','nobody'];
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_presence is not null and not (p_presence = any(v_allowed)) then
    raise exception 'Invalid presence visibility';
  end if;
  if p_last_seen is not null and not (p_last_seen = any(v_allowed)) then
    raise exception 'Invalid last seen visibility';
  end if;
  if p_profile_photo is not null and not (p_profile_photo = any(v_allowed)) then
    raise exception 'Invalid profile photo visibility';
  end if;
  if p_about is not null and not (p_about = any(v_allowed)) then
    raise exception 'Invalid about visibility';
  end if;
  if p_story is not null and not (p_story = any(v_allowed)) then
    raise exception 'Invalid story visibility';
  end if;
  if p_leaderboard is not null and not (p_leaderboard = any(v_allowed)) then
    raise exception 'Invalid leaderboard visibility';
  end if;

  if p_presence = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'presence') then
    raise exception 'only requires at least one person';
  end if;
  if p_last_seen = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'last_seen') then
    raise exception 'only requires at least one person';
  end if;
  if p_profile_photo = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'profile_photo') then
    raise exception 'only requires at least one person';
  end if;
  if p_about = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'about') then
    raise exception 'only requires at least one person';
  end if;
  if p_story = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'story') then
    raise exception 'only requires at least one person';
  end if;
  if p_leaderboard = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'leaderboard') then
    raise exception 'only requires at least one person';
  end if;

  update profiles set
    presence_visibility = coalesce(p_presence, presence_visibility),
    last_seen_visibility = coalesce(p_last_seen, last_seen_visibility),
    profile_photo_visibility = coalesce(p_profile_photo, profile_photo_visibility),
    about_visibility = coalesce(p_about, about_visibility),
    story_visibility = coalesce(p_story, story_visibility),
    leaderboard_visibility = coalesce(p_leaderboard, leaderboard_visibility),
    read_receipts_enabled = coalesce(p_read_receipts, read_receipts_enabled)
  where id = auth.uid();
  return public.my_privacy_settings();
end;
$function$;

-- ── 4) my_privacy_settings ──
create or replace function public.my_privacy_settings()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'presence', coalesce(presence_visibility, 'everyone'),
    'last_seen', coalesce(last_seen_visibility, 'everyone'),
    'profile_photo', coalesce(profile_photo_visibility, 'everyone'),
    'about', coalesce(about_visibility, 'everyone'),
    'story', coalesce(story_visibility, 'everyone'),
    'leaderboard', coalesce(leaderboard_visibility, 'everyone'),
    'read_receipts', coalesce(read_receipts_enabled, true),
    'exclusions', coalesce((select jsonb_object_agg(field, ids) from (
      select field, jsonb_agg(excluded_uid) as ids
      from profile_privacy_exclusions
      where owner_id = auth.uid()
      group by field
    ) x), '{}'::jsonb)
  )
  from profiles where id = auth.uid();
$function$;

-- ── 5) privacy_can_view: +mapping leaderboard ──
create or replace function public.privacy_can_view(
  p_owner uuid,
  p_field text,
  p_viewer uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_vis text;
  v_friend boolean;
  v_excluded boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

  if coalesce((select privacy_bypass_enabled from public.app_settings where id = 'global'), false)
     and coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    return true;
  end if;

  -- Foto profil: mitra chat private boleh saling lihat. Hanya profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1 from public.private_chats c
    where c.participants @> array[p_owner, p_viewer]::uuid[]
  ) then
    return true;
  end if;

  -- Foto profil: anggota GRUP/room sama boleh saling lihat. Hanya profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1
      from public.room_members a
      join public.room_members b on b.room_id = a.room_id
     where a.user_id = p_owner and b.user_id = p_viewer
  ) then
    return true;
  end if;

  select case p_field
    when 'presence' then presence_visibility
    when 'last_seen' then last_seen_visibility
    when 'profile_photo' then profile_photo_visibility
    when 'about' then about_visibility
    when 'story' then story_visibility
    when 'leaderboard' then leaderboard_visibility
    else 'nobody'
  end into v_vis
  from public.profiles where id = p_owner;

  v_vis := coalesce(v_vis, 'nobody');
  if v_vis = 'everyone' then return true; end if;
  if v_vis = 'nobody' then return false; end if;

  v_excluded := exists (
    select 1 from public.profile_privacy_exclusions e
    where e.owner_id = p_owner
      and e.excluded_uid = p_viewer
      and e.field = p_field
  );

  if v_vis = 'everyone_except' then
    return not v_excluded;
  end if;

  if v_vis = 'only' then
    return v_excluded;
  end if;

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end; $function$;

-- ── 6) replace_privacy_exclusions: +'leaderboard' ──
create or replace function public.replace_privacy_exclusions(p_field text, p_uids uuid[])
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_field not in ('presence','last_seen','profile_photo','about','story','leaderboard') then raise exception 'Invalid privacy field'; end if;
  delete from profile_privacy_exclusions where owner_id = auth.uid() and field = p_field;
  insert into profile_privacy_exclusions(owner_id, excluded_uid, field)
  select auth.uid(), x, p_field from unnest(coalesce(p_uids, '{}'::uuid[])) x
  where x <> auth.uid()
  on conflict do nothing;
  return public.my_privacy_settings();
end;
$function$;

-- ── 7) activity_leaderboard: filter privacy_can_view('leaderboard') ──
create or replace function public.activity_leaderboard(
  p_scope text default 'weekly',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  me jsonb;
  v_excl uuid[];
  v_dummy uuid[];
  v_lim int;
  v_off int;
  v_since timestamptz;
  v_me uuid := auth.uid();
begin
  v_lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_off := greatest(coalesce(p_offset, 0), 0);
  v_since := case when p_scope = 'alltime' then null
                  else (now() - interval '7 days') end;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  with raw as (
    select p.author_id as uid, count(*)::int as posts, 0::int as stories, 0::int as priv, 0::int as room
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    select s.author_id, 0, count(*)::int, 0, 0
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    select m.sender_id, 0, 0, count(*)::int, 0
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, 0, 0, 0, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
  ),
  agg as (
    select uid,
           sum(posts)::int as posts,
           sum(stories)::int as stories,
           sum(priv)::int as priv,
           sum(room)::int as room,
           (sum(posts) + sum(stories) + sum(priv) + sum(room))::int as score
      from raw
     group by uid
  ),
  final as (
    select
      p.id, p.nickname, p.avatar, p.country, p.is_registered, p.gender,
      a.posts, a.stories, a.priv, a.room, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
      -- Hormati privasi Top Aktif (nobody/friends/only/kecuali).
      and public.privacy_can_view(p.id, 'leaderboard', v_me)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', f.rank,
      'uid', f.id,
      'nickname', f.nickname,
      'avatar', f.avatar,
      'country', f.country,
      'gender', f.gender,
      'is_registered', f.is_registered,
      'score', f.score,
      'post_count', f.posts,
      'story_count', f.stories,
      'msg_private', f.priv,
      'msg_room', f.room
    ) order by f.rank), '[]'::jsonb)
    into result
    from final f
   where f.rank > v_off and f.rank <= v_off + v_lim;

  with raw as (
    select p.author_id as uid, count(*)::int s
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    select s.author_id, count(*)::int
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    select m.sender_id, count(*)::int
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
  ),
  agg as ( select uid, sum(s)::int as score from raw group by uid ),
  final as (
    select p.id, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
      and public.privacy_can_view(p.id, 'leaderboard', v_me)
  )
  select jsonb_build_object('rank', f.rank, 'score', f.score)
    into me
    from final f
   where f.id = v_me;

  return jsonb_build_object('scope', p_scope, 'entries', result, 'me', me);
end;
$function$;

-- Verifikasi setelah apply:
--   select my_privacy_settings()->>'leaderboard';
--   select public.activity_leaderboard('weekly', 5, 0);