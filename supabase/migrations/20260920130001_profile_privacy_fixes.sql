-- menyentuh: nearby_users
-- ============================================================
-- PERBAIKAN privacy (lanjutan 20260920130000).
--
-- 1) nearby_users: ORDER BY memakai ordinal 12 padahal hanya 11 kolom →
--    error saat dipanggil. Kembalikan urut jarak terdekat.
-- 2) get_online_users: akses `anon` terlanjur dicabut (perilaku lama:
--    authenticated + anon). Anonim tidak punya privacy sendiri, jadi
--    hanya boleh melihat pemilik ber-visibility 'everyone'. Sekaligus
--    filter privacy di-INLINE (bukan fungsi per baris) supaya listing
--    online tetap cepat.
-- 3) profile_public: sertakan kembali `share_location` + `points` milik
--    SENDIRI saja (dipakai Nearby toggle & fallback bonus login harian).
-- 4) mark_chat_read: saat read receipt OFF, `unread_counts` penerima
--    TETAP dinolkan (badge pesan harus hilang); hanya `last_read_at`
--    yang tidak ditulis supaya centang biru tidak muncul di pengirim.
-- ============================================================

-- ── 1) nearby_users: fix ordinal + privacy ──
create or replace function public.nearby_users(p_radius_km double precision default 10)
 returns table(uid uuid, nickname text, gender text, age integer, country text, city text,
   status text, avatar text, is_registered boolean, last_seen timestamptz, distance_km double precision)
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  radius_m double precision;
  v_excl uuid[];
begin
  if me is null then raise exception 'Not authenticated'; end if;
  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon into my_lat, my_lon
  from public.profiles p where p.id = me;

  if my_lat is null or my_lon is null then
    raise exception 'No location';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  return query
  select
    p.id,
    p.nickname,
    p.gender,
    p.age,
    p.country,
    p.city,
    p.status,
    case when public.privacy_can_view(p.id, 'profile_photo', me) then p.avatar else '' end,
    p.is_registered,
    case when public.privacy_can_view(p.id, 'last_seen', me) then p.last_seen else null end,
    (earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) / 1000.0) as distance_km
  from public.profiles p
  where p.id <> me
    and p.lat is not null
    and p.lon is not null
    and coalesce(p.share_location, false) = true
    and p.status in ('online', 'idle')
    and p.last_seen >= now() - interval '30 minutes'
    and public.privacy_can_view(p.id, 'presence', me)
    and not (p.id = any(v_excl))
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by 11 asc
  limit 100;
end;
$fn$;

-- ── 2) get_online_users: inline privacy + dukungan anon ──
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
    'country', s.country, 'city', s.city, 'status', s.status,
    'avatar', case when s.photo_ok then s.avatar else '' end,
    'is_registered', s.is_registered,
    'last_seen', case when s.seen_ok then s.last_seen else null end
  ) order by s.last_seen desc), '[]'::jsonb) into rows
  from (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen,
      (p.profile_photo_visibility = 'everyone'
        or (p.profile_photo_visibility = 'except' and ep.owner_id is null)
        or (p.profile_photo_visibility = 'friends' and public._are_friends(v_me, p.id))) as photo_ok,
      (p.last_seen_visibility = 'everyone'
        or (p.last_seen_visibility = 'except' and es.owner_id is null)
        or (p.last_seen_visibility = 'friends' and public._are_friends(v_me, p.id))) as seen_ok
    from public.profiles p
    left join public.profile_privacy_exclusions ep
      on ep.owner_id = p.id and ep.excluded_uid = v_me and ep.field = 'profile_photo'
    left join public.profile_privacy_exclusions es
      on es.owner_id = p.id and es.excluded_uid = v_me and es.field = 'last_seen'
    where p.id <> v_me
      and p.status in ('online', 'idle')
      and p.last_seen >= now() - interval '30 minutes'
      and (p_country is null or p.country = p_country)
      and (
        p.presence_visibility = 'everyone'
        or (p.presence_visibility = 'except' and not exists (
              select 1 from public.profile_privacy_exclusions e
              where e.owner_id = p.id and e.excluded_uid = v_me and e.field = 'presence'))
        or (p.presence_visibility = 'friends' and public._are_friends(v_me, p.id))
      )
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

-- ── 3) profile_public: sertakan share_location + points milik sendiri ──
create or replace function public.profile_public(p_user uuid default auth.uid())
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare
  r public.profiles%rowtype;
  me uuid := auth.uid();
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;
  return jsonb_build_object(
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
    'points', case when r.id = me then r.points else 0 end,
    'share_location', case when r.id = me then r.share_location else false end,
    'followers_count', r.followers_count,
    'following_count', r.following_count,
    'subscriber_count', r.subscriber_count,
    'subscription_price', r.subscription_price,
    'friends_count', r.friends_count
  );
end;
$fn$;

-- ── 4) mark_chat_read: badge tetap hilang walau receipt OFF ──
create or replace function public.mark_chat_read(p_chat_id text, p_uid uuid)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  me uuid := auth.uid();
  receipts_on boolean;
begin
  if me is null or p_uid <> me then raise exception 'Unauthorized'; end if;
  if not exists (
    select 1 from public.private_chats c
    where c.chat_id = p_chat_id and me = any(c.participants)
  ) then
    raise exception 'Unauthorized';
  end if;

  receipts_on := coalesce(
    (select read_receipts_enabled from public.profiles where id = me), true);

  update public.private_chats
  set unread_counts = jsonb_set(
        coalesce(unread_counts, '{}'::jsonb),
        array[p_uid::text], '0'::jsonb, true),
      last_read_at = case
        when receipts_on then jsonb_set(
          coalesce(last_read_at, '{}'::jsonb),
          array[p_uid::text], to_jsonb(now()::text), true)
        else last_read_at
      end
  where chat_id = p_chat_id;

  return jsonb_build_object('ok', true, 'receipts', receipts_on);
end;
$fn$;

revoke execute on function public.mark_chat_read(text, uuid) from public, anon;
grant execute on function public.mark_chat_read(text, uuid) to authenticated;
