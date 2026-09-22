-- menyentuh: nearby_users
-- ============================================================
-- Privasi "Orang Sekitar" (nearby) — 2 lubang ditutup.
--
-- 1) nearby_users: TANPA filter `blocks` → user yang saling memblokir
--    tetap muncul di daftar Orang Sekitar dan bisa diklik untuk chat
--    (chat-nya ditolak server, tapi keberadaan + jaraknya tetap bocor).
--    Tambah filter dua arah, idiom sama dengan story_slides.
--
-- 2) nearby_users: gate berbagi TIDAK ditegakkan di server. Skrining
--    "harus bagikan lokasi dulu" hanya di UI (nearby_screen `if (!_shareOn)`),
--    sehingga panggilan RPC langsung tetap bisa melihat orang lain walau
--    viewer `share_location = false` → bisa "mengintip" tanpa ikut terlihat.
--    Sekarang: pemanggil WAJIB share_location=true, kalau tidak →
--    raise 'Share required' (string baru, dibedakan dari 'No location').
--
-- 3) get_online_users: lubang blokir yang SAMA (daftar online tidak memfilter
--    `blocks`). Tambah filter blokir dua arah di kedua overload. Tidak ada
--    gate share di sini (online list bukan fitur lokasi).
--
-- Versi dasar = snapshot terbaru (nearby_users @20260920130001,
-- get_online_users @20260920130004) + tambahan di atas. JANGAN copy dari
-- migrasi lama (risiko cabang hilang) — lihat AGENTS.md § SQL.
-- ============================================================

-- ── 1‑2) nearby_users: filter blocks + gate berbagi ──
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
  my_share boolean;
  radius_m double precision;
  v_excl uuid[];
begin
  if me is null then raise exception 'Not authenticated'; end if;
  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon, coalesce(p.share_location, false)
    into my_lat, my_lon, my_share
  from public.profiles p where p.id = me;

  -- Gate simetris: tidak boleh melihat orang lain bila tidak membagikan
  -- lokasi sendiri. Diperiksa SEBELUM cek lokasi (pesan lebih tepat).
  if not coalesce(my_share, false) then
    raise exception 'Share required';
  end if;

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
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    )
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by 11 asc
  limit 100;
end;
$fn$;

revoke execute on function public.nearby_users(double precision) from public, anon;
grant execute on function public.nearby_users(double precision) to authenticated;

-- ── 3) get_online_users: filter blocks (dua overload) ──
-- Dasar = snapshot @20260920130004 (5 nilai privacy) + filter blocks.
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

create or replace function public.get_online_users(p_limit int default 100)
returns jsonb language sql security definer set search_path = public as $$
  select public.get_online_users(null::text, p_limit);
$$;

revoke execute on function public.get_online_users(text, int) from public;
revoke execute on function public.get_online_users(int) from public;
grant execute on function public.get_online_users(text, int) to authenticated, anon;
grant execute on function public.get_online_users(int) to authenticated, anon;
