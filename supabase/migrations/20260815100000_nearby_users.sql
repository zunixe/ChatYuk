-- ============================================================
-- ChatYuk: Fitur "Orang Sekitar" (nearby users)
-- - Aktifkan extension cube + earthdistance untuk hitung jarak geo.
-- - RPC nearby_users(radius_km): user online/idle dalam radius dari
--   lokasi pemanggil, urut terdekat, sertakan jarak (km).
-- Syarat: pemanggil punya lat/lon; target punya lat/lon & share_location.
-- ============================================================

create extension if not exists cube;
create extension if not exists earthdistance;

-- Index untuk mempercepat pencarian radius (ll_to_earth immutable).
create index if not exists idx_profiles_earth
  on public.profiles using gist (ll_to_earth(lat, lon))
  where lat is not null and lon is not null;

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
  radius_m double precision;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Batasi radius wajar: 1..500 km.
  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon into my_lat, my_lon
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
    and p.status in ('online', 'idle')
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by distance_km asc
  limit 100;
end;
$$;

revoke execute on function public.nearby_users(double precision) from public, anon;
grant execute on function public.nearby_users(double precision) to authenticated;
