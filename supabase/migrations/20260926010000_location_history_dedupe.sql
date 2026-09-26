-- ============================================================
-- History lokasi: stop spam baris diam-di-tempat.
--
-- Temuan: user_location_history berisi ratusan baris koordinat IDENTIK
-- yang ditulis tiap 1-2 detik (idle→online flap + ping), mis. 1389 baris
-- / 7 hari untuk 1 user dengan 18 titik beda. Pengambilan GPS-nya BENAR
-- (titik berubah saat user bergerak) — yang salah laju tulisnya.
--
-- Fix (server, berlaku semua versi app): profiles lat/lon TETAP diupdate
-- tiap panggilan (nearby butuh posisi segar), tapi baris history hanya
-- disisipkan bila BERGERAK (>50m dari titik terakhir) ATAU titik terakhir
-- sudah tua (>30 mnt, heartbeat). Tidak menyentuh fungsi FROZEN.
-- ============================================================

create or replace function public.update_my_location(p_lat double precision, p_lon double precision, p_source text, p_ip text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_ip text := nullif(trim(coalesce(p_ip, '')), '');
  v_last_lat double precision;
  v_last_lon double precision;
  v_last_at timestamptz;
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

  -- History: lewati bila diam (<50m) dan titik terakhir masih segar
  -- (<30 mnt). Badan fungsi di atas disalin persis dari versi live.
  select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
    from public.user_location_history
   where user_id = uid
   order by created_at desc limit 1;
  if found
     and earth_distance(
           ll_to_earth(v_last_lat, v_last_lon),
           ll_to_earth(p_lat, p_lon)) < 50
     and now() - v_last_at < interval '30 minutes' then
    return;
  end if;
  insert into public.user_location_history (user_id, lat, lon, loc_source)
  values (uid, p_lat, p_lon, p_source);
end;
$$;

revoke execute on function public.update_my_location(double precision, double precision, text, text) from public, anon;
grant execute on function public.update_my_location(double precision, double precision, text, text) to authenticated;
