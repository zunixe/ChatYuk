-- ============================================================
-- ChatYuk: Konsistensi status online — Orang Sekitar vs Pengguna Online
-- - nearby_users sebelumnya hanya filter status in ('online','idle')
--   tanpa cutoff last_seen, sehingga user dengan status "online" basi
--   (app ditutup paksa, last_seen > 30 menit) tetap muncul di Orang
--   Sekitar tapi tidak di daftar Pengguna Online (getOnlineUsers
--   memakai cutoff last_seen 30 menit).
-- - Fix: tambah filter last_seen >= now() - 30 menit supaya kedua
--   daftar konsisten.
-- Catatan: diaplikasikan manual via Supabase Dashboard (Playwright),
-- CLI `supabase db query --linked` hang di mesin dev.
-- ============================================================

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
    -- Konsisten dengan getOnlineUsers: last_seen dalam 30 menit terakhir.
    and p.last_seen >= now() - interval '30 minutes'
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by distance_km asc
  limit 100;
end;
$$;

revoke execute on function public.nearby_users(double precision) from public, anon;
grant execute on function public.nearby_users(double precision) to authenticated;