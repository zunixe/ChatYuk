-- ============================================================
-- Kartu Online + halaman lain: tampilkan jumlah FRIENDS & FOLLOWERS.
--
-- LATAR: kartu Online (get_online_users) tidak mengirim friends_count /
-- followers_count — padahal kolomnya ada di profiles & UserModel sudah
-- memparse-nya. Fitur: tampilkan "1.2K Followers · 34 Friends" (gaya IG).
--
-- YANG DIUBAH:
--   1. get_online_users: +friends_count +followers_count (salin PERSIS dari
--      live + 2 kolom candidates + 2 field output).
--   2. RPC baru social_counts_uids(p_uids uuid[]): map uid → {friends,
--      followers} untuk halaman non-Online (list chat/social/room member).
--      Read-only, SECURITY DEFINER (data publik, tanpa gate privasi).
--
-- menyentuh: get_online_users
--
-- CARA APPLY: supabase db push / Management API. Idempotent.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_online_users(p_country text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rows jsonb;
  v_me uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
  v_bypass boolean;
begin
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;

  -- Bypass admin dicek SEKALI (dulu dicek di dalam privacy_can_view 800x).
  v_bypass :=
    coalesce(
      (select privacy_bypass_enabled from public.app_settings where id = 'global'),
      false
    )
    and coalesce(auth.email(), '') = 'zunixe@gmail.com';

  with candidates as (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen, p.about,
      p.friends_count, p.followers_count,
      coalesce(p.presence_visibility, 'nobody')      as presence_vis,
      coalesce(p.last_seen_visibility, 'nobody')     as seen_vis,
      coalesce(p.profile_photo_visibility, 'nobody') as photo_vis,
      coalesce(p.about_visibility, 'nobody')         as about_vis
    from public.profiles p
    where p.id <> v_me
      and p.status in ('online', 'idle')
      and p.last_seen >= now() - interval '30 minutes'
      and (p_country is null or p.country = p_country)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_me)
      )
    order by p.last_seen desc
    limit p_limit
  ),
  -- Foto: mitra chat private (1 query utk semua kandidat, bukan per-row).
  chat_partners as (
    select distinct c2.uid
    from public.private_chats c
    cross join lateral unnest(c.participants) as c2(uid)
    where c.participants @> array[v_me]::uuid[]
  ),
  -- Foto: anggota room/grup sama (1 query).
  room_mates as (
    select distinct b.user_id as uid
    from public.room_members a
    join public.room_members b on b.room_id = a.room_id
    where a.user_id = v_me
  ),
  -- Exclusions per (owner, field) untuk semua kandidat (1 query).
  excl as (
    select e.owner_id, e.field
    from public.profile_privacy_exclusions e
    where e.excluded_uid = v_me
  ),
  -- Status friend (mutual follow) untuk semua kandidat (1 query).
  friends as (
    select f1.followee_id as uid
    from public.follows f1
    join public.follows f2
      on f1.followee_id = f2.follower_id
     and f1.follower_id = f2.followee_id
    where f1.follower_id = v_me
  ),
  resolved as (
    select
      s.*,
      (v_bypass
        or s.id in (select uid from friends))            as is_friend,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'presence')      as excl_presence,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'last_seen')     as excl_seen,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'profile_photo') as excl_photo,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'about')         as excl_about,
      (s.id in (select uid from chat_partners)
        or s.id in (select uid from room_mates))         as photo_partner
    from candidates s
  ),
  flags as (
    select
      r.*,
      -- presence
      (v_bypass or r.presence_vis = 'everyone'
        or (r.presence_vis in ('friends','friends_except') and r.is_friend
            and (r.presence_vis = 'friends' or not r.excl_presence))
        or (r.presence_vis = 'everyone_except' and not r.excl_presence)
        or (r.presence_vis = 'only' and r.excl_presence)
      ) as presence_ok,
      -- last_seen
      (v_bypass or r.seen_vis = 'everyone'
        or (r.seen_vis in ('friends','friends_except') and r.is_friend
            and (r.seen_vis = 'friends' or not r.excl_seen))
        or (r.seen_vis = 'everyone_except' and not r.excl_seen)
        or (r.seen_vis = 'only' and r.excl_seen)
      ) as seen_ok,
      -- about
      (v_bypass or r.about_vis = 'everyone'
        or (r.about_vis in ('friends','friends_except') and r.is_friend
            and (r.about_vis = 'friends' or not r.excl_about))
        or (r.about_vis = 'everyone_except' and not r.excl_about)
        or (r.about_vis = 'only' and r.excl_about)
      ) as about_ok,
      -- photo: mitra chat/room SELALU boleh; selain itu aturan visibilitas.
      (v_bypass or r.photo_partner or r.photo_vis = 'everyone'
        or (r.photo_vis in ('friends','friends_except') and r.is_friend
            and (r.photo_vis = 'friends' or not r.excl_photo))
        or (r.photo_vis = 'everyone_except' and not r.excl_photo)
        or (r.photo_vis = 'only' and r.excl_photo)
      ) as photo_ok
    from resolved r
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id, 'nickname', f.nickname, 'gender', f.gender, 'age', f.age,
    'country', f.country, 'city', f.city,
    'status', case when f.presence_ok then f.status else 'offline' end,
    'avatar', case when f.photo_ok then f.avatar else '' end,
    'is_registered', f.is_registered,
    'last_seen', case when f.seen_ok then f.last_seen else null end,
    'about', case when f.about_ok then f.about else '' end,
    'friends_count', f.friends_count,
    'followers_count', f.followers_count
  ) order by f.last_seen desc), '[]'::jsonb)
  into rows
  from flags f
  -- Filter presence SAMA seperti sebelumnya (hormati privasi presence).
  where f.presence_ok;

  return rows;
end;
$function$;

-- ── RPC baru: social counts per-uid (bulk) ──

create or replace function public.social_counts_uids(p_uids uuid[])
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object(
    'friends',   coalesce(p.friends_count, 0),
    'followers', coalesce(p.followers_count, 0)
  )), '{}'::jsonb)
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]));
$function$;

revoke execute on function public.social_counts_uids(uuid[]) from public, anon;
grant execute on function public.social_counts_uids(uuid[]) to authenticated;
