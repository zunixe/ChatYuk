-- Fix: "Orang Sekitar" tidak mendeteksi siapa pun.
--
-- GEJALA: fitur Orang Sekitar kosong walau ada user online/idle di dekat
-- (mis. radius 500 km tetap "tidak ada").
--
-- AKAR MASALAH (data, bukan bug kode): RPC mensyaratkan `share_location=true`
-- DUA ARAH (viewer & target). Di produksi hanya ~24 dari 231 user yang
-- share_location=true, dan hanya 1 yang eligible online → daftar nyaris
-- selalu kosong.
--
-- KEPUTUSAN PRODUK: tampilkan semua user yang PUNYA koordinat lat/lon
-- (dari GPS) tanpa wajib menekan "bagikan lokasi". Filter yang dipertahankan:
--   - punya lat & lon (tanpa lokasi tidak bisa dihitung jarak)
--   - status in ('online','idle') + last_seen <= 30 menit (konsisten dgn
--     daftar Online)
--   - privacy presence (privacy_can_view presence)
--   - blokir dua arah
--   - exclude admin-excluded
-- Viewer sendiri cukup punya lokasi (my_lat/my_lon not null); tidak lagi
-- wajib share_location=true.
--
-- Versi dasar = snapshot terbaru (nearby_users @20260922140000).

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

  select p.lat, p.lon
    into my_lat, my_lon
  from public.profiles p where p.id = me;

  -- Viewer WAJIB punya lokasi sendiri (agar jarak bisa dihitung & simetris).
  -- Tidak lagi mewajibkan share_location=true (lihat keputusan produk di atas).
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
