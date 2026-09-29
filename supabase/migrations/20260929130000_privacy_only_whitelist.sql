-- ============================================================
-- Privasi: ganti mode otomatis "circle" (Kenalan) → "only"
-- (Hanya orang tertentu) — daftar putih yang dipilih manual.
--
-- MASALAH YANG DIPERBAIKI:
--   1) RPC update_privacy_settings di DB live MASIH hanya menerima 4 nilai
--      lama (everyone/friends/except/nobody) → memilih 'circle',
--      'everyone_except', atau 'friends_except' SELALU gagal
--      ('Invalid presence visibility') dan tidak tersimpan. Ini akar
--      keluhan "tak bisa pilih kenalan". Allowlist kini = 6 nilai.
--   2) 'circle' (teman|follower|subscriber|pernah chat) → 'only'
--      (hanya orang yang dipilih manual).
--
-- MAKNA 'only': field terlihat HANYA bila viewer ada di
--   profile_privacy_exclusions(owner, field, viewer). Daftar kosong =
--   tak ada yang bisa lihat → update_privacy_settings MENOLAK 'only' bila
--   belum ada minimal 1 orang (cegah "Hanya orang tertentu (0)" yang
--   membingungkan; client mengirim daftar dulu baru nilai visibility).
--
-- SUMBER: privacy_can_view + get_online_users = @20260929120000 (cabang
--   'circle' diganti 'only'); update_privacy_settings = live
--   @20260920130000 (allowlist diperbaiki + guard daftar kosong);
--   privacy_excludable_users = @20260920130004 (+ follower & baris 'only').
--   _privacy_is_circle DI-DROP (tak ada pemakai lain — diverifikasi live).
--
-- menyentuh: privacy_can_view
-- (tidak di frozen_functions.txt, tapi diganti lintas-migrasi: header +
--  review diff untuk cegah cabang hilang, pola Lapis 2.)
--
-- CARA APPLY: Management API (CLI db push HANG).
-- ROLLBACK: constraint 6-nilai dengan 'circle', re-apply gate/online
--   @20260929120000 (helper _privacy_is_circle), re-apply
--   update_privacy_settings @20260920130000.
-- ============================================================

-- ── 1) Constraint: 'circle' → 'only'; migrasikan data (idempoten) ──
alter table public.profiles drop constraint profiles_privacy_visibility_check;
alter table public.profiles drop constraint if exists profiles_privacy_visibility_check_old;
update public.profiles set presence_visibility = 'only' where presence_visibility = 'circle';
update public.profiles set last_seen_visibility = 'only' where last_seen_visibility = 'circle';
update public.profiles set profile_photo_visibility = 'only' where profile_photo_visibility = 'circle';
update public.profiles set about_visibility = 'only' where about_visibility = 'circle';
update public.profiles set story_visibility = 'only' where story_visibility = 'circle';
alter table public.profiles add constraint profiles_privacy_visibility_check check (
    presence_visibility in ('everyone','everyone_except','friends','friends_except','only','nobody')
and last_seen_visibility in ('everyone','everyone_except','friends','friends_except','only','nobody')
and profile_photo_visibility in ('everyone','everyone_except','friends','friends_except','only','nobody')
and about_visibility in ('everyone','everyone_except','friends','friends_except','only','nobody')
and story_visibility in ('everyone','everyone_except','friends','friends_except','only','nobody'));

-- ── 2) Helper circle dihapus (sudah tak dipakai) ──
drop function if exists public._privacy_is_circle(uuid, uuid);

-- ── 3) Gate + cabang 'only' (sisanya identik @20260924230000/_circle). ──
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

  -- 'only': HANYA orang di daftar (daftar putih) — kebalikan 'everyone_except'.
  if v_vis = 'only' then
    return v_excluded;
  end if;

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  -- 'friends_except': hanya teman, kecuali yang masuk daftar.
  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end; $$;

-- ── 4) get_online_users: cermin 'only' (join exclusion SAMA dipakai sebagai
--      daftar putih — tak perlu join baru). Basis @20260929120000. ──
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
        or (p.profile_photo_visibility = 'only'
            and ep.owner_id is not null)) as photo_ok,
      (p.last_seen_visibility = 'everyone'
        or (p.last_seen_visibility = 'everyone_except' and es.owner_id is null)
        or (p.last_seen_visibility in ('friends','friends_except')
            and fr.is_friend and es.owner_id is null)
        or (p.last_seen_visibility = 'only'
            and es.owner_id is not null)) as seen_ok,
      (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null)
        or (p.presence_visibility = 'only'
            and ee.owner_id is not null)) as presence_ok,
      (p.about_visibility = 'everyone'
        or (p.about_visibility = 'everyone_except' and ea.owner_id is null)
        or (p.about_visibility in ('friends','friends_except')
            and fr.is_friend and ea.owner_id is null)
        or (p.about_visibility = 'only'
            and ea.owner_id is not null)) as about_ok
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
        or (p.presence_visibility = 'only'
            and ee.owner_id is not null))
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

-- ── 5) update_privacy_settings: allowlist 6 nilai + guard 'only' kosong.
--      (Mengganti definisi live @20260920130000 yang masih 4 nilai.) ──
create or replace function public.update_privacy_settings(
  p_presence text default null,
  p_last_seen text default null,
  p_profile_photo text default null,
  p_about text default null,
  p_story text default null,
  p_read_receipts boolean default null
)
returns jsonb language plpgsql security definer set search_path = public as $fn$
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

  -- 'only' tanpa orang = tak ada yang bisa lihat → tolak (client kirim
  -- daftar dulu). Mencegah tile "Hanya orang tertentu (0)" yang bingung.
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

-- ── 6) privacy_excludable_users: kandidat picker diperluas —
--      teman (mutual) | follower-ku | subscriber aktifku |
--      anon yang pernah chat | uid di daftar 'only' saya (agar baris
--      whitelist lama tetap bisa dilihat/dihapus). Basis @20260920130004. ──
create or replace function public.privacy_excludable_users()
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'uid', x.id,
        'nickname', x.nickname,
        'avatar', x.avatar,
        'is_registered', x.is_registered,
        'is_friend', x.is_friend
      )
      order by x.is_friend desc, x.nickname
    ),
    '[]'::jsonb
  )
  from (
    select
      p.id,
      p.nickname,
      p.avatar,
      p.is_registered,
      public._privacy_are_friends(auth.uid(), p.id) as is_friend
    from public.profiles p
    where p.id <> auth.uid()
      and (
        -- teman (mutual follow)
        public._privacy_are_friends(auth.uid(), p.id)
        -- orang yang follow saya
        or exists (
          select 1 from public.follows f
          where f.follower_id = p.id and f.followee_id = auth.uid()
        )
        -- subscriber aktif saya
        or exists (
          select 1 from public.subscriptions s
          where s.subscriber_id = p.id and s.creator_id = auth.uid()
            and s.expires_at > now()
        )
        -- anon yang pernah chat dengan saya
        or (
          p.is_registered = false
          and exists (
            select 1 from public.private_chats c
            where auth.uid() = any(c.participants)
              and p.id = any(c.participants)
          )
        )
        -- sudah ada di daftar "hanya orang tertentu" saya (field apa pun)
        or exists (
          select 1 from public.profile_privacy_exclusions e
          where e.owner_id = auth.uid() and e.excluded_uid = p.id
        )
      )
    limit 300
  ) x;
$fn$;

-- ── 7) Grants (revoke execute fungsi = rutin; grant hanya authenticated). ──
revoke execute on function public.privacy_can_view(uuid, text, uuid) from public, anon;
grant execute on function public.privacy_can_view(uuid, text, uuid) to authenticated;
revoke execute on function public.get_online_users(text, int) from public, anon;
grant execute on function public.get_online_users(text, int) to anon, authenticated, service_role;
revoke execute on function public.update_privacy_settings(text, text, text, text, text, boolean) from public, anon;
grant execute on function public.update_privacy_settings(text, text, text, text, text, boolean) to authenticated;
revoke execute on function public.privacy_excludable_users() from public, anon;
grant execute on function public.privacy_excludable_users() to authenticated;
