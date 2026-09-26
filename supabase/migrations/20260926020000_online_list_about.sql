-- ============================================================
-- Online list: tampilkan Tentang (about) di kartu Online.
--
-- LATAR: kartu daftar Online hanya menampilkan nama + gender/umur/kota.
-- User meminta isi Tentang tampil di bawah baris gender agar kartu lebih
-- informatif (polaprivasi sama seperti avatar/last_seen: hormati
-- about_visibility + daftar pengecualian).
--
-- PERUBAHAN (kolom output baru, tanpa ubah signature/filter):
--   1) get_online_users(...) → tambah key 'about': isi bila about_ok,
--      '' bila tidak (pola sama dengan photo_ok/seen_ok/presence_ok +
--      join exclusions field='about').
--   2) presence_for(...) → tambah key 'about' via privacy_can_view
--      (jalur fast-path presence harus konsisten dengan slow path RPC).
--
-- Bukan fungsi FROZEN (tidak ada di scripts/frozen_functions.txt).
-- Grants dipertahankan (get_online_users: anon+authenticated,
-- presence_for: authenticated).
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

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
            and fr.is_friend and ep.owner_id is null)) as photo_ok,
      (p.last_seen_visibility = 'everyone'
        or (p.last_seen_visibility = 'everyone_except' and es.owner_id is null)
        or (p.last_seen_visibility in ('friends','friends_except')
            and fr.is_friend and es.owner_id is null)) as seen_ok,
      (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null)) as presence_ok,
      (p.about_visibility = 'everyone'
        or (p.about_visibility = 'everyone_except' and ea.owner_id is null)
        or (p.about_visibility in ('friends','friends_except')
            and fr.is_friend and ea.owner_id is null)) as about_ok
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
      and (p_country is null or p.country = p_country)
      and (p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'everyone_except' and ee.owner_id is null)
        or (p.presence_visibility in ('friends','friends_except')
            and fr.is_friend and ee.owner_id is null))
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

create or replace function public.presence_for(p_uids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  me uuid := auth.uid();
  invisible_uid uuid;
  arr jsonb;
begin
  -- Invisible (mis. admin mode) → hilangkan dari hasil, konsisten dgn
  -- get_online_users yang memfilter invisible lewat status.
  select s.invisible_admin_uid into invisible_uid
    from public.app_settings s where s.id = 'global';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',        p.id,
    'nickname',  p.nickname,
    'gender',    p.gender,
    'age',       p.age,
    'country',   p.country,
    'city',      p.city,
    'is_registered', p.is_registered,
    'avatar',    case when public.privacy_can_view(p.id, 'profile_photo', me)
                      then p.avatar else '' end,
    'status',    case when public.privacy_can_view(p.id, 'presence', me)
                      then p.status else 'offline' end,
    'last_seen', case when public.privacy_can_view(p.id, 'last_seen', me)
                      then p.last_seen else null end,
    'about',     case when public.privacy_can_view(p.id, 'about', me)
                      then p.about else '' end
  )), '[]'::jsonb) into arr
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]))
    and p.id <> coalesce(me, '00000000-0000-0000-0000-000000000000'::uuid)
    and (invisible_uid is null or p.id <> invisible_uid)
    -- Hormati blokir dua arah (sama seperti get_online_users).
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    );

  return arr;
end;
$fn$;

revoke execute on function public.presence_for(uuid[]) from public, anon;
grant execute on function public.presence_for(uuid[]) to authenticated, service_role;
