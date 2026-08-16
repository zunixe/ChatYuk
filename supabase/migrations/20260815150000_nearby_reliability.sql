-- ============================================================
-- ChatYuk: Nearby lebih andal
--
-- Masalah: "kadang kedetect kadang engga" walau dua hape deketan.
--   a) Lokasi IP tidak stabil (provider rate-limit → lokasi null atau
--      koordinat beda jauh) → di luar radius → tidak muncul.
--   b) Hape yang dibackground → status 'offline' → ikut difilter.
--
-- Fix:
--   1. update_my_location menerima p_ip → simpan ip_address user.
--   2. nearby_users:
--      - SELALU sertakan user dengan ip_address SAMA (satu WiFi =
--        pasti dekat), berapa pun jarak koordinatnya.
--      - Sertakan user 'offline' yang masih aktif < 15 menit.
-- ============================================================

-- 1. update_my_location + simpan IP publik
create or replace function public.update_my_location(
  p_lat double precision,
  p_lon double precision,
  p_source text,
  p_ip text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;
  update public.profiles
  set lat = p_lat,
      lon = p_lon,
      loc_source = p_source,
      loc_updated_at = now(),
      ip_address = coalesce(nullif(p_ip, ''), ip_address)
  where id = uid;
end;
$$;
revoke execute on function public.update_my_location(double precision, double precision, text) from public, anon;
revoke execute on function public.update_my_location(double precision, double precision, text, text) from public, anon;
grant execute on function public.update_my_location(double precision, double precision, text) to authenticated;
grant execute on function public.update_my_location(double precision, double precision, text, text) to authenticated;

-- 2. nearby_users: same-IP selalu muncul + offline < 15 menit tetap muncul
create or replace function public.nearby_users(p_radius_km double precision default 10)
returns table (
  uid uuid,
  nickname text,
  gender text,
  age int,
  country text,
  city text,
  status text,
  avatar text,
  is_registered boolean,
  last_seen timestamptz,
  distance_km double precision
)
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  my_ip text;
  radius_m double precision;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon, p.ip_address into my_lat, my_lon, my_ip
  from public.profiles p where p.id = me;

  if my_lat is null or my_lon is null then
    raise exception 'No location';
  end if;

  return query
  select
    p.id,
    p.nickname,
    p.gender,
    p.age,
    p.country,
    p.city,
    p.status,
    p.avatar,
    p.is_registered,
    p.last_seen,
    (earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) / 1000.0) as distance_km
  from public.profiles p
  where p.id <> me
    and p.lat is not null
    and p.lon is not null
    and coalesce(p.share_location, false) = true
    and (
      p.status in ('online', 'idle')
      or (p.status = 'offline' and p.last_seen > now() - interval '15 minutes')
    )
    and (
      -- Satu WiFi / IP publik sama → pasti dekat, tak peduli koordinat.
      (my_ip is not null and p.ip_address = my_ip)
      or (
        earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
        and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
      )
    )
  order by distance_km asc
  limit 100;
end;
$$;
revoke execute on function public.nearby_users(double precision) from public, anon;
grant execute on function public.nearby_users(double precision) to authenticated;
