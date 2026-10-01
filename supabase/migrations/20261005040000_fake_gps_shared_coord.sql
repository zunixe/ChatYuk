-- ============================================================
-- Deteksi FAKE GPS lanjutan (gap yang ditemukan 2026-10-05).
--
-- TEMUAN (audit live): 77 dari 348 user ber-GPS duduk di 19 koordinat yang
-- dipakai >1 orang. Dua cluster besar:
--   (-6.9097, 107.5649) → 35 akun (Padalarang) — sama persis ~5 desimal,
--   (37.4220, -122.0841) → 10 akun — DEFAULT Android Emulator (Google HQ).
-- Semua lolos `location_mocked=false` karena heuristik lama hanya mendeteksi
-- is_mocked / accuracy_zero / impossible_speed / spoof_delta(IP>500km).
--
-- YANG DITAMBAH (ke `update_my_location`, hanya untuk source='gps'):
--   (e) static_coord   : update terbaru identik (< 8 m) dgn titik terakhir,
--                        berulang ≥3× berturut → khas koordinat beku/emulator.
--   (f) known_emulator : koordinat ≈ default emulator (37.4220,-122.0841)
--                        atau default umum lain (dalam radius 100 m).
--   (g) shared_coord   : koordinat (< 25 m) dipakai ≥3 user BERBEDA → farm
--                        emulator / fake GPS massal. Dicek ke profiles.
--
-- Plus `admin_flag_shared_locations()` — helper backfill SEKALI JALAN (dipakai
-- admin/scrip) untuk menandai cluster existing. Hanya MENANDAI (badge),
-- TIDAK menghapus.
--
-- Sumber disalin PERSIS dari live (`update_my_location` @20261002060000),
-- hanya penambahan cabang. Bukan FROZEN.
-- CARA APPLY: Management API (1 statement create fn + 1 create helper +
--   revoke/grant). Lihat APPLIED_VIA_API.md.
-- ============================================================

create or replace function public.update_my_location(
  p_lat double precision,
  p_lon double precision,
  p_source text,
  p_ip text default null,
  p_mocked boolean default false,
  p_accuracy integer default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  v_ip text := nullif(trim(coalesce(p_ip, '')), '');
  v_last_lat double precision;
  v_last_lon double precision;
  v_last_at timestamptz;
  v_reason text := null;
  v_flag boolean := false;
  v_speed_mps double precision;
  v_same_streak int;
  v_shared int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;

  -- Heuristik (hanya relevan untuk source gps; IP = perkiraan, tak dinilai).
  if p_source = 'gps' then
    -- (a) device melaporkan mock provider.
    if coalesce(p_mocked, false) then
      v_flag := true; v_reason := 'is_mocked';
    end if;
    -- (b) akurasi 0 / negatif persis (khas mock).
    if p_accuracy is not null and p_accuracy <= 0 then
      v_flag := true;
      v_reason := case when v_reason is null then 'accuracy_zero'
                       else v_reason || ',accuracy_zero' end;
    end if;

    -- Ambil titik GPS terakhir (untuk c & e).
    select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
      from public.user_location_history
     where user_id = uid and loc_source = 'gps'
     order by created_at desc limit 1;

    -- (c) kecepatan mustahil (>250 m/s ≈ 900 km/jam) dari titik terakhir.
    if found and v_last_at is not null
       and now() - v_last_at >= interval '10 seconds' then
      v_speed_mps := earth_distance(
        ll_to_earth(v_last_lat, v_last_lon), ll_to_earth(p_lat, p_lon))
        / extract(epoch from (now() - v_last_at));
      if v_speed_mps > 250 then
        v_flag := true;
        v_reason := case when v_reason is null then 'impossible_speed'
                         else v_reason || ',impossible_speed' end;
      end if;
    end if;

    -- (d) GPS vs IP terakhir berbeda > 500 km (spoof).
    if exists (
      select 1 from public.profiles
      where id = uid and lat_ip is not null and lon_ip is not null)
    then
      if (
        select earth_distance(ll_to_earth(lat_ip, lon_ip), ll_to_earth(p_lat, p_lon))
        from public.profiles where id = uid) > 500000 then
        v_flag := true;
        v_reason := case when v_reason is null then 'spoof_delta'
                         else v_reason || ',spoof_delta' end;
      end if;
    end if;

    -- (f) koordinat ≈ default emulator (radius 100 m). Default khas:
    --     Android Emulator (Googleplex), dan default SDK lain yang lazim.
    if (earth_distance(ll_to_earth(37.4220, -122.0841), ll_to_earth(p_lat, p_lon)) < 100)
       or (earth_distance(ll_to_earth(37.4219983, -122.084), ll_to_earth(p_lat, p_lon)) < 100)
       or (earth_distance(ll_to_earth(0, 0), ll_to_earth(p_lat, p_lon)) < 100) then
      v_flag := true;
      v_reason := case when v_reason is null then 'known_emulator'
                       else v_reason || ',known_emulator' end;
    end if;

    -- (e) static_coord: 3 update GPS terakhir berturut identik (< 8 m) →
    --     koordinat beku (khas emulator/static fake). Dihitung dari history.
    select count(*) into v_same_streak
      from (
        select lat, lon
          from public.user_location_history
         where user_id = uid and loc_source = 'gps'
         order by created_at desc limit 3
      ) h
     where earth_distance(ll_to_earth(h.lat, h.lon), ll_to_earth(p_lat, p_lon)) < 8;
    if v_same_streak >= 3 then
      v_flag := true;
      v_reason := case when v_reason is null then 'static_coord'
                       else v_reason || ',static_coord' end;
    end if;

    -- (g) shared_coord: koordinat (< 25 m) dipakai ≥3 user BERBEDA → farm.
    select count(distinct p.id) into v_shared
      from public.profiles p
     where p.id <> uid
       and p.lat_gps is not null
       and earth_distance(ll_to_earth(p.lat_gps, p.lon_gps), ll_to_earth(p_lat, p_lon)) < 25;
    if v_shared >= 2 then  -- 2 lain + diri = 3 total
      v_flag := true;
      v_reason := case when v_reason is null then 'shared_coord'
                       else v_reason || ',shared_coord' end;
    end if;
  end if;

  if p_source = 'gps' then
    update public.profiles
       set lat_gps        = p_lat,
           lon_gps        = p_lon,
           gps_updated_at = now(),
           lat            = p_lat,
           lon            = p_lon,
           loc_source     = 'gps',
           loc_updated_at = now(),
           location_mocked      = v_flag,
           location_mock_reason = v_reason,
           location_accuracy_m  = p_accuracy,
           location_flagged_at  = case when v_flag then now()
                                       else location_flagged_at end
     where id = uid;
  else
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

  -- History: lewati bila diam (<50m) & titik terakhir masih segar (<30 mnt),
  -- TAPI tetap catat bila ada flag mock (agar riwayat audit tak bolong).
  select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
    from public.user_location_history
   where user_id = uid
   order by created_at desc limit 1;
  if found
     and earth_distance(
           ll_to_earth(v_last_lat, v_last_lon),
           ll_to_earth(p_lat, p_lon)) < 50
     and now() - v_last_at < interval '30 minutes'
     and not v_flag then
    return;
  end if;
  insert into public.user_location_history
    (user_id, lat, lon, loc_source, location_mocked, mock_reason, accuracy_m)
  values (uid, p_lat, p_lon, p_source, v_flag, v_reason, p_accuracy);
end;
$function$;

revoke execute on function public.update_my_location(double precision, double precision, text, text, boolean, integer) from public, anon;
grant execute on function public.update_my_location(double precision, double precision, text, text, boolean, integer) to authenticated;

-- ── Backfill SEKALI JALAN: tandai cluster koordinat bersama (≥3 user, <25 m)
--    sebagai location_mocked + alasan 'shared_coord' (kecuali yang sudah
--    punya alasan lain). Hanya MENANDAI (badge admin), tidak menghapus.
--    Dipanggil admin/service_role.
create or replace function public.admin_flag_shared_locations(p_min_users int default 3)
returns int
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_count int := 0;
begin
  if coalesce(auth.email(),'') <> 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  with grp as (
    select round(lat_gps::numeric, 4) la, round(lon_gps::numeric, 4) lo,
           count(*) n
      from public.profiles
     where lat_gps is not null and loc_source = 'gps'
     group by 1, 2
    having count(*) >= greatest(coalesce(p_min_users,3), 2)
  )
  update public.profiles p
     set location_mocked = true,
         location_mock_reason =
           case when p.location_mock_reason is null
                  or p.location_mock_reason = ''
                then 'shared_coord'
                when position('shared_coord' in p.location_mock_reason) > 0
                then p.location_mock_reason
                else p.location_mock_reason || ',shared_coord' end,
         location_flagged_at = coalesce(p.location_flagged_at, now())
    from grp g
   where round(p.lat_gps::numeric, 4) = g.la
     and round(p.lon_gps::numeric, 4) = g.lo
     and p.loc_source = 'gps'
     and p.location_mocked = false;
  get diagnostics v_count = row_count;
  return v_count;
end;
$fn$;

revoke execute on function public.admin_flag_shared_locations(int) from public, anon;
grant execute on function public.admin_flag_shared_locations(int) to authenticated, service_role;

-- Verifikasi setelah apply:
--   select public.admin_flag_shared_locations(3);          -- backfill (sekali)
--   select count(*) from public.profiles where location_mocked;
--   select location_mock_reason, count(*) from public.profiles
--    where location_mocked group by 1 order by 2 desc;
