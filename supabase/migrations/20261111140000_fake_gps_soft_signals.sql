-- ============================================================
-- Perbaikan deteksi FAKE GPS — false positive "orang di lokasi yang sama".
--
-- TEMUAN (audit live 2026-11-11):
--   * static_coord SENDIRIAN menandai 20 user; akurasi rata-rata 277 m
--     (maks 2000 m) → user ASLI yang diam di rumah dengan fix network/kasar
--     (izin "lokasi perkiraan" Android 12+ di-snap ke grid → koordinat
--     identik tiap update). Riwayat juga hanya dicatat tiap 30 mnt saat
--     diam, jadi 3 baris "identik" = cuma ±1 jam di rumah.
--   * shared_coord SENDIRIAN menandai 11 user ber-akurasi 5–17 m → orang
--     serumah / sekos / sekantor (Wi-Fi positioning memberi titik SAMA ke
--     semua HP di jaringan yang sama). Termasuk multi-akun di 1 HP & akun
--     dummy dev.
--   * spoof_delta: IP seluler Indonesia sering ter-geolokasi ke Jakarta →
--     user di luar Jawa "beda >500 km" padahal asli.
--   * impossible_speed: tidak memperhitungkan akurasi — lompatan fix kasar
--     (cell tower, km) dalam 10 dtk dianggap mustahil.
--
-- PERBAIKAN (update_my_location, source='gps'):
--   HARD (cukup 1 → flag): is_mocked, accuracy_zero, known_emulator,
--     impossible_speed (kini dikurangi akurasi kedua titik, jarak efektif
--     wajib > 5 km & jeda ≥ 30 dtk).
--   SOFT (butuh ≥ 2 sinyal soft → flag; sendirian TIDAK menandai):
--     static_coord : 5 fix PRESISI (akurasi ≤ 50 m) berturut < 2 m.
--     shared_coord : titik (< 3 m) dipakai ≥ 3 user lain yang fix-nya
--                    presisi & segar (≤ 30 hari), BUKAN akun dummy, dan
--                    BUKAN akun yang pernah login di HP yang sama.
--     spoof_delta  : GPS vs IP segar (≤ 1 hari) beda > 1500 km.
--   Reason hanya ditulis bila ter-flag (supaya badge tetap konsisten).
--
-- BACKFILL: `admin_reevaluate_location_flags()` membuang reason soft lama
--   (dihitung dgn aturan longgar) dan mencabut flag yang tak punya reason
--   HARD. Soft dihitung ulang otomatis di update lokasi berikutnya.
--   `admin_flag_shared_locations` (backfill lama, aturan longgar) dialihkan
--   ke fungsi ini supaya tak bisa menandai ulang secara massal.
--
-- Sumber: update_my_location LIVE (= 20261005040000). Bukan FROZEN.
-- CARA APPLY: Management API. ROLLBACK: re-apply 20261005040000.
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
  v_last_acc integer;
  v_hard text[] := '{}';
  v_soft text[] := '{}';
  v_reason text := null;
  v_flag boolean := false;
  v_dist double precision;
  v_dt double precision;
  v_n int;
  v_same int;
  v_shared int;
  v_precise boolean := p_accuracy is not null and p_accuracy > 0 and p_accuracy <= 50;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;

  if p_source = 'gps' then
    -- ── HARD ──
    -- (a) device melaporkan mock provider.
    if coalesce(p_mocked, false) then
      v_hard := array_append(v_hard, 'is_mocked');
    end if;
    -- (b) akurasi 0 / negatif persis (khas mock).
    if p_accuracy is not null and p_accuracy <= 0 then
      v_hard := array_append(v_hard, 'accuracy_zero');
    end if;
    -- (f) koordinat ≈ default emulator (radius 100 m).
    if (earth_distance(ll_to_earth(37.4220, -122.0841), ll_to_earth(p_lat, p_lon)) < 100)
       or (earth_distance(ll_to_earth(37.4219983, -122.084), ll_to_earth(p_lat, p_lon)) < 100)
       or (earth_distance(ll_to_earth(0, 0), ll_to_earth(p_lat, p_lon)) < 100) then
      v_hard := array_append(v_hard, 'known_emulator');
    end if;
    -- (c) kecepatan mustahil — jarak dikurangi akurasi kedua titik (fix
    --     kasar bisa meleset km), jarak efektif > 5 km, jeda ≥ 30 dtk,
    --     kecepatan > 300 m/s (di atas pesawat jet).
    select lat, lon, created_at, accuracy_m
      into v_last_lat, v_last_lon, v_last_at, v_last_acc
      from public.user_location_history
     where user_id = uid and loc_source = 'gps'
     order by created_at desc limit 1;
    if found and v_last_at is not null
       and now() - v_last_at >= interval '30 seconds' then
      v_dist := earth_distance(
                  ll_to_earth(v_last_lat, v_last_lon), ll_to_earth(p_lat, p_lon))
                - coalesce(nullif(p_accuracy, 0), 100)
                - coalesce(nullif(v_last_acc, 0), 100);
      v_dt := extract(epoch from (now() - v_last_at));
      if v_dist > 5000 and v_dist / v_dt > 300 then
        v_hard := array_append(v_hard, 'impossible_speed');
      end if;
    end if;

    -- ── SOFT ──
    -- (d) GPS vs IP SEGAR beda > 1500 km (geolokasi IP seluler ID kasar).
    select earth_distance(ll_to_earth(lat_ip, lon_ip), ll_to_earth(p_lat, p_lon))
      into v_dist
      from public.profiles
     where id = uid and lat_ip is not null and lon_ip is not null
       and ip_updated_at > now() - interval '1 day';
    if v_dist is not null and v_dist > 1500000 then
      v_soft := array_append(v_soft, 'spoof_delta');
    end if;

    -- (e) static_coord: fix ini + 5 fix GPS terakhir semuanya PRESISI dan
    --     < 2 m → koordinat beku. Fix kasar/network wajar identik → abaikan.
    if v_precise then
      select count(*), count(*) filter (
               where h.accuracy_m is not null and h.accuracy_m > 0
                 and h.accuracy_m <= 50
                 and earth_distance(ll_to_earth(h.lat, h.lon),
                                    ll_to_earth(p_lat, p_lon)) < 2)
        into v_n, v_same
        from (
          select lat, lon, accuracy_m
            from public.user_location_history
           where user_id = uid and loc_source = 'gps'
           order by created_at desc limit 5
        ) h;
      if v_n >= 5 and v_same >= 5 then
        v_soft := array_append(v_soft, 'static_coord');
      end if;
    end if;

    -- (g) shared_coord: titik (< 3 m) dipakai ≥ 3 user lain dengan fix
    --     presisi & segar. Abaikan dummy & akun se-HP (multi-akun ≠ fake).
    if v_precise then
      select count(distinct p.id) into v_shared
        from public.profiles p
       where p.id <> uid
         and p.lat_gps is not null
         and p.gps_updated_at > now() - interval '30 days'
         and p.location_accuracy_m is not null
         and p.location_accuracy_m > 0 and p.location_accuracy_m <= 50
         and not exists (select 1 from public.dummy_accounts du where du.uid = p.id)
         and not exists (
           select 1
             from public.user_devices d1
             join public.user_devices d2 on d2.install_id = d1.install_id
            where d1.user_id = uid and d2.user_id = p.id)
         and earth_distance(ll_to_earth(p.lat_gps, p.lon_gps),
                            ll_to_earth(p_lat, p_lon)) < 3;
      if v_shared >= 3 then
        v_soft := array_append(v_soft, 'shared_coord');
      end if;
    end if;

    v_flag := cardinality(v_hard) > 0 or cardinality(v_soft) >= 2;
    if v_flag then
      v_reason := array_to_string(v_hard || v_soft, ',');
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

-- ── Backfill: buang reason SOFT lama, cabut flag tanpa reason HARD ──
create or replace function public.admin_reevaluate_location_flags()
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

  with r as (
    select p.id,
           nullif(array_to_string(array(
             select t from unnest(string_to_array(p.location_mock_reason, ',')) t
              where t in ('is_mocked','accuracy_zero','known_emulator','impossible_speed')
           ), ','), '') as hard
      from public.profiles p
     where p.location_mocked
  )
  update public.profiles p
     set location_mocked      = (r.hard is not null),
         location_mock_reason = r.hard
    from r
   where p.id = r.id
     and p.location_mock_reason is distinct from r.hard;
  get diagnostics v_count = row_count;
  return v_count;
end;
$fn$;

revoke execute on function public.admin_reevaluate_location_flags() from public, anon;
grant execute on function public.admin_reevaluate_location_flags() to authenticated, service_role;

-- Backfill lama (aturan longgar ≥3 user / 11 m) → dialihkan; tak lagi menandai.
create or replace function public.admin_flag_shared_locations(p_min_users int default 3)
returns int
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if coalesce(auth.email(),'') <> 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;
  return public.admin_reevaluate_location_flags();
end;
$fn$;

revoke execute on function public.admin_flag_shared_locations(int) from public, anon;
grant execute on function public.admin_flag_shared_locations(int) to authenticated, service_role;

-- Setelah apply (sekali):
--   select public.admin_reevaluate_location_flags();
--   select location_mock_reason, count(*) from public.profiles
--    where location_mocked group by 1 order by 2 desc;
