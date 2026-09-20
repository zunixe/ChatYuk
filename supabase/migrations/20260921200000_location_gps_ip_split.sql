-- GPS dicatat terpisah dari IP — "GPS terakhir" tidak boleh hilang saat
-- fallback IP menulis.
--
-- MASALAH NYATA (terukur di live DB 2026-09-21):
--   1. `user_location_history` = 0 baris padahal 66 user ber-loc_source
--      'gps'. Sebab: migrasi 20260815150000 membuat OVERLOAD 4-arg
--      `update_my_location` TANPA menyalin logika INSERT history. Client
--      memanggil yang 4-arg → history tidak pernah tercatat.
--   2. GPS tertimpa IP: saat GPS gagal fix, fallback IP menulis ke
--      `profiles.lat/lon` yang SAMA → koordinat GPS terakhir hilang.
--
-- PERBAIKAN:
--   * Kolom terpisah: lat_gps/lon_gps/gps_updated_at + lat_ip/lon_ip/
--     ip_updated_at. Keduanya disimpan; tidak saling menimpa.
--   * `lat/lon` (dipakai peta admin & nearby_users) = GPS terakhir bila
--     ada, else IP — backward compatible, tidak mengubah kontrak pembaca.
--   * History dicatat untuk KEDUA sumber (satu jalur, tidak ada overload
--     tanpa history lagi).
--   * Overload lama di-DROP supaya tidak ada ambigu.
--
-- `nearby_users` FROZEN — tidak disentuh (tetap membaca lat/lon/loc_source
-- yang kontraknya dipertahankan).

-- ── 1. Kolom terpisah GPS vs IP ──
alter table public.profiles
  add column if not exists lat_gps double precision;
alter table public.profiles
  add column if not exists lon_gps double precision;
alter table public.profiles
  add column if not exists gps_updated_at timestamptz;
alter table public.profiles
  add column if not exists lat_ip double precision;
alter table public.profiles
  add column if not exists lon_ip double precision;
alter table public.profiles
  add column if not exists ip_updated_at timestamptz;

-- ── 2. Backfill: data lama masuk ke kolom sesuai sumbernya ──
update public.profiles
   set lat_gps = lat, lon_gps = lon, gps_updated_at = loc_updated_at
 where loc_source = 'gps' and lat is not null and lat_gps is null;

update public.profiles
   set lat_ip = lat, lon_ip = lon, ip_updated_at = loc_updated_at
 where loc_source = 'ip' and lat is not null and lat_ip is null;

-- ── 3. RPC satu jalur (selalu catat history) ──
drop function if exists public.update_my_location(
  double precision, double precision, text);
drop function if exists public.update_my_location(
  double precision, double precision, text, text);

create or replace function public.update_my_location(
  p_lat double precision,
  p_lon double precision,
  p_source text,
  p_ip text default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare
  uid uuid := auth.uid();
  v_ip text := nullif(trim(coalesce(p_ip, '')), '');
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;

  if p_source = 'gps' then
    -- GPS: simpan ke kolom GPS + jadikan posisi utama (prioritas GPS).
    update public.profiles
       set lat_gps        = p_lat,
           lon_gps        = p_lon,
           gps_updated_at = now(),
           lat            = p_lat,
           lon            = p_lon,
           loc_source     = 'gps',
           loc_updated_at = now()
     where id = uid;
  else
    -- IP: simpan ke kolom IP. `lat/lon` hanya diisi bila BELUM ada GPS —
    -- GPS terakhir tidak boleh tertimpa perkiraan IP.
    update public.profiles
       set lat_ip        = p_lat,
           lon_ip        = p_lon,
           ip_updated_at = now(),
           ip_address    = coalesce(v_ip, ip_address),
           lat           = coalesce(lat_gps, p_lat),
           lon           = coalesce(lon_gps, p_lon),
           loc_source    = case when lat_gps is not null then 'gps' else 'ip' end,
           loc_updated_at = now()
     where id = uid;
  end if;

  -- History posisi tiap update (gps maupun ip) — satu-satunya jalur tulis.
  insert into public.user_location_history (user_id, lat, lon, loc_source)
  values (uid, p_lat, p_lon, p_source);
end;
$fn$;

revoke execute on function public.update_my_location(
  double precision, double precision, text, text) from public, anon;
grant execute on function public.update_my_location(
  double precision, double precision, text, text) to authenticated, service_role;

-- ── 4. Admin: ringkasan GPS vs IP per user (untuk panel) ──
create or replace function public.admin_location_sources()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'gps', (select count(*) from public.profiles where lat_gps is not null),
    'ip',  (select count(*) from public.profiles where lat_ip is not null),
    'none',(select count(*) from public.profiles
             where lat_gps is null and lat_ip is null),
    'history', (select count(*) from public.user_location_history),
    'history_gps', (select count(*) from public.user_location_history
                     where loc_source = 'gps')
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_location_sources() from public, anon;
grant execute on function public.admin_location_sources() to authenticated, service_role;
