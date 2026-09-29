-- ============================================================
-- Privasi mode "circle" (Kenalan) — nilai visibility ke-6.
--
-- MAKNA: field terlihat hanya bila viewer adalah salah satu:
--   teman (mutual follow) | follower-ku | subscriber-ku AKTIF |
--   pernah 1:1 chat (termasuk anon — cabang chat buta registered/anon).
-- Selain itu = stranger → di-mask seperti biasa. Self selalu lolos
-- (cabang existing). Berlaku untuk kelima field visibility.
--
-- YANG DISENGAJA TIDAK DIUBAH:
--   - arti friends/friends_except/everyone(_except)/nobody (cabang lama
--     byte-identik dengan @20260924230000);
--   - TIDAK ada circle_except (daftar kecuali tetap milik *_except;
--     potong-paksa pakai blokir);
--   - get_online_users: hanya tambah OR 'circle' (filter & flag lain utuh).
--
-- SUMBER: privacy_can_view @20260924230000_admin_privacy_bypass.sql,
--   get_online_users + presence_for @20260926020000_online_list_about.sql.
--   presence_for/avatar_for/avatars_for/nearby_users/story_tray/story_slides/
--   profile_public memanggil gate LANGSUNG -> ikut tanpa diubah.
--   nearby @20260928100000, story_slides frozen (tak tersentuh).
--   Index idx_private_chats_participants_gin SUDAH ADA (no-op di bawah).
--
-- menyentuh: privacy_can_view
-- (tidak ada di frozen_functions.txt, tapi diganti lintas-migrasi:
--  header + review diff untuk cegah cabang hilang, pola Lapis 2.)
--
-- CARA APPLY: Management API (CLI db push HANG).
-- ROLLBACK: nilai 'circle' kembali dilarang via constraint 5-nilai
--   (set visibility='friends' dulu untuk baris yang sudah memakai circle),
--   lalu re-apply gate @20260924230000 + get_online_users @20260926020000.
-- ============================================================

-- ── 1) Nilai baru 'circle' (6 nilai). Tabel kecil (~300 baris): validasi ms.
alter table public.profiles drop constraint profiles_privacy_visibility_check;
alter table public.profiles add constraint profiles_privacy_visibility_check check (
    presence_visibility in ('everyone','everyone_except','friends','friends_except','circle','nobody')
and last_seen_visibility in ('everyone','everyone_except','friends','friends_except','circle','nobody')
and profile_photo_visibility in ('everyone','everyone_except','friends','friends_except','circle','nobody')
and about_visibility in ('everyone','everyone_except','friends','friends_except','circle','nobody')
and story_visibility in ('everyone','everyone_except','friends','friends_except','circle','nobody'));

-- ── 2) Helper circle: mutual TERCakup follows-inbound (A<->B pasti ada
-- baris follower A->B), jadi cukup 3 EXISTS termurah dulu (PK, PK, GIN).
create or replace function public._privacy_is_circle(p_viewer uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select
    exists (select 1 from public.follows f
             where f.follower_id = p_viewer and f.followee_id = p_owner)
    or exists (select 1 from public.subscriptions s
             where s.subscriber_id = p_viewer and s.creator_id = p_owner
               and s.expires_at > now())
    or exists (select 1 from public.private_chats c
             where c.participants @> array[p_owner, p_viewer]);
$fn$;

revoke execute on function public._privacy_is_circle(uuid, uuid) from public, anon;
grant execute on function public._privacy_is_circle(uuid, uuid) to authenticated, service_role;

-- ── 3) Gate + cabang 'circle' (sisanya identik @20260924230000).
create or replace function public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_vis text;
  v_friend boolean;
  v_excluded boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

  -- Bypass admin: flag ON + viewer admin → semua field terlihat.
  -- (auth.email() = pemanggil, walau SECURITY DEFINER.)
  if coalesce((select privacy_bypass_enabled from public.app_settings where id = 'global'), false)
     and coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    return true;
  end if;

  select case p_field
    when 'presence' then presence_visibility
    when 'last_seen' then last_seen_visibility
    when 'profile_photo' then profile_photo_visibility
    when 'about' then about_visibility
    when 'story' then story_visibility
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

  -- 'everyone_except': semua orang boleh, KECUALI yang masuk daftar.
  if v_vis = 'everyone_except' then
    return not v_excluded;
  end if;

  -- 'circle': kenalan saja (tanpa daftar kecuali — konsisten 'friends').
  if v_vis = 'circle' then
    return public._privacy_is_circle(p_viewer, p_owner);
  end if;

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  -- 'friends_except': hanya teman, kecuali yang masuk daftar.
  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end; $$;

-- ── 4) get_online_users: cermin 'circle' (identik @20260926020000 + 5 OR).
create or replace function public.get_online_users(p_country text DEFAULT NULL::text, p_limit integer DEFAULT 100)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  rows jsonb;
  v_me uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
begin
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'nickname', s.nickname, 'gender', s.gender, 'age', s.age,
    'country', s.country, 'city', s.city,
    'status', case when s.presence_ok then s.status else 'offline' end,
    'avatar', case when s.photo_ok then s.avatar else '' end,
    'is_registered', s.is_registered,
    'last_seen', case when s.seen_ok then s.last_seen else null end,
    'about', case when s.about_ok then s.about else '' end
  ) order by s.last_seen desc), '[]'::jsonb) into rows
  from (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen, p.about,
      (p.profile_photo_visibility = 'everyone'
        or (p.profile_photo_visibility = 'everyone_except' and ep.owner_id is null)
        or (p.profile_photo_visibility in ('friends','friends_except')
            and fr.is_friend and ep.owner_id is null)
        or (p.profile_photo_visibility = 'circle'
            and public._privacy_is_circle(v_me, p.id))) as photo_ok,
      (p.last_seen_visibility = 'everyone'
        or (p.last_seen_visibility = 'everyone_except' and es.owner_id is null)
        or (p.last_seen_visibility in ('friends','friends_except')
            and fr.is_friend and es.owner_id is null)
        or (p.last_seen_visibility = 'circle'
            and public._privacy_is_circle(v_me, p.id))) as seen_ok,
      (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null)
        or (p.presence_visibility = 'circle'
            and public._privacy_is_circle(v_me, p.id))) as presence_ok,
      (p.about_visibility = 'everyone'
        or (p.about_visibility = 'everyone_except' and ea.owner_id is null)
        or (p.about_visibility in ('friends','friends_except')
            and fr.is_friend and ea.owner_id is null)
        or (p.about_visibility = 'circle'
            and public._privacy_is_circle(v_me, p.id))) as about_ok
    from public.profiles p
    left join public.profile_privacy_exclusions ep
      on ep.owner_id = p.id and ep.excluded_uid = v_me and ep.field = 'profile_photo'
    left join public.profile_privacy_exclusions es
      on es.owner_id = p.id and es.excluded_uid = v_me and es.field = 'last_seen'
    left join public.profile_privacy_exclusions ee
      on ee.owner_id = p.id and ee.excluded_uid = v_me and ee.field = 'presence'
    left join public.profile_privacy_exclusions ea
      on ea.owner_id = p.id and ea.excluded_uid = v_me and ea.field = 'about'
    left join lateral (
      select exists (
        select 1
        from public.follows f1
        join public.follows f2
          on f1.followee_id = f2.follower_id
         and f1.follower_id = f2.followee_id
        where f1.follower_id = v_me and f1.followee_id = p.id
      ) as is_friend
    ) fr on true
    where p.id <> v_me
      and p.status in ('online', 'idle')
      and p.last_seen >= now() - interval '30 minutes'
      and (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null)
        or (p.presence_visibility = 'circle'
            and public._privacy_is_circle(v_me, p.id)))
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_me)
      )
    order by p.last_seen desc
    limit p_limit
  ) s;
  return rows;
end;
$fn$;

revoke execute on function public.get_online_users(text, int) from public, anon;
grant execute on function public.get_online_users(text, int) to anon, authenticated, service_role;

-- ── 5) Index GIN participants SUDAH ADA (idx_private_chats_participants_gin,
-- diverifikasi live 2026-09-29) -> no-op aman bila belum ada.
create index if not exists idx_private_chats_participants_gin
  on public.private_chats using gin (participants);
