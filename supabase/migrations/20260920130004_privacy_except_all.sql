-- ============================================================
-- Privacy: opsi LENGKAP 5 nilai + pengecualian bisa memilih ANON.
--
-- Nilai baru (menggantikan 'except'):
--   'everyone'        → semua orang
--   'everyone_except' → semua orang KECUALI daftar (teman & anon boleh masuk)
--   'friends'         → hanya teman (mutual follow)
--   'friends_except'  → teman, KECUALI daftar (dulu bernama 'except')
--   'nobody'          → tidak ada
--
-- Catatan: 'except' lama diperlakukan sebagai 'friends_except' dan
-- dimigrasi ke nilai barunya, jadi pilihan pengguna yang sudah ada aman.
-- ============================================================

-- ── 1) Longgarkan constraint dulu (supaya migrasi nilai aman) ──
alter table public.profiles
  drop constraint if exists profiles_privacy_visibility_check;

-- ── 2) Migrasi nilai lama 'except' → 'friends_except' ──
update public.profiles set presence_visibility = 'friends_except' where presence_visibility = 'except';
update public.profiles set last_seen_visibility = 'friends_except' where last_seen_visibility = 'except';
update public.profiles set profile_photo_visibility = 'friends_except' where profile_photo_visibility = 'except';
update public.profiles set about_visibility = 'friends_except' where about_visibility = 'except';
update public.profiles set story_visibility = 'friends_except' where story_visibility = 'except';

-- ── 3) Constraint baru (5 nilai) ──
alter table public.profiles
  add constraint profiles_privacy_visibility_check check (
    presence_visibility in ('everyone','everyone_except','friends','friends_except','nobody')
    and last_seen_visibility in ('everyone','everyone_except','friends','friends_except','nobody')
    and profile_photo_visibility in ('everyone','everyone_except','friends','friends_except','nobody')
    and about_visibility in ('everyone','everyone_except','friends','friends_except','nobody')
    and story_visibility in ('everyone','everyone_except','friends','friends_except','nobody')
  );

-- ── 4) Field pengecualian tetap sama; tidak ada perubahan tabel ──

-- ── 5) privacy_can_view: 5 cabang ──
create or replace function public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_vis text;
  v_friend boolean;
  v_excluded boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

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
  -- (anon pun bisa dikecualikan — daftar boleh berisi teman maupun anon.)
  if v_vis = 'everyone_except' then
    return not v_excluded;
  end if;

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  -- 'friends_except': hanya teman, kecuali yang masuk daftar.
  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end;
$fn$;

-- ── 6) Daftar yang bisa dikecualikan: TEMAN + ANON yang pernah chat ──
-- Dipakai picker untuk kedua opsi "kecuali..." (semua/teman).
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
        -- anon yang pernah chat dengan saya
        or (
          p.is_registered = false
          and exists (
            select 1 from public.private_chats c
            where auth.uid() = any(c.participants)
              and p.id = any(c.participants)
          )
        )
      )
    limit 300
  ) x;
$fn$;

-- ── 7) get_online_users: set-based, dukung 5 nilai ──
create or replace function public.get_online_users(p_country text default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = public as $fn$
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
    'last_seen', case when s.seen_ok then s.last_seen else null end
  ) order by s.last_seen desc), '[]'::jsonb) into rows
  from (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen,
      (p.profile_photo_visibility = 'everyone'
        or (p.profile_photo_visibility = 'everyone_except' and ep.owner_id is null)
        or (p.profile_photo_visibility in ('friends','friends_except')
            and fr.is_friend and ep.owner_id is null)) as photo_ok,
      (p.last_seen_visibility = 'everyone'
        or (p.last_seen_visibility = 'everyone_except' and es.owner_id is null)
        or (p.last_seen_visibility in ('friends','friends_except')
            and fr.is_friend and es.owner_id is null)) as seen_ok,
      (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null)) as presence_ok
    from public.profiles p
    left join public.profile_privacy_exclusions ep
      on ep.owner_id = p.id and ep.excluded_uid = v_me and ep.field = 'profile_photo'
    left join public.profile_privacy_exclusions es
      on es.owner_id = p.id and es.excluded_uid = v_me and es.field = 'last_seen'
    left join public.profile_privacy_exclusions ee
      on ee.owner_id = p.id and ee.excluded_uid = v_me and ee.field = 'presence'
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
      and (p_country is null or p.country = p_country)
      and (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null))
    order by p.last_seen desc
    limit p_limit
  ) s;
  return rows;
end;
$fn$;

create or replace function public.get_online_users(p_limit int default 100)
returns jsonb language sql security definer set search_path = public as $$
  select public.get_online_users(null::text, p_limit);
$$;

revoke execute on function public.get_online_users(text, int) from public;
revoke execute on function public.get_online_users(int) from public;
grant execute on function public.get_online_users(text, int) to authenticated, anon;
grant execute on function public.get_online_users(int) to authenticated, anon;

revoke execute on function public.privacy_excludable_users() from public, anon;
grant execute on function public.privacy_excludable_users() to authenticated;
revoke execute on function public.privacy_can_view(uuid, text, uuid) from public, anon;
grant execute on function public.privacy_can_view(uuid, text, uuid) to authenticated;
