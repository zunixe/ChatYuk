-- Lapis 3: deteksi Fake GPS (flag + heuristik) — 20261002060000.
-- Jalankan: scripts/run_sql_tests.sh fake_gps_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
-- Aturan: is_mocked (device) | accuracy_zero | impossible_speed | spoof_delta.
--   Hanya MENANDAI (location_mocked) — tak memblokir. History mencatat flag.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000031'::uuid, 'TEST GpsUser', 'online');

-- (a) device lapor mock → is_mocked.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000031","email":"t@t.local","role":"authenticated"}', false);
select public.update_my_location(-6.2, 106.8, 'gps', null, true, 25);
select supabase_tests.check('is_mocked → flag + reason',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mocked = true
            and location_mock_reason like '%is_mocked%'));

-- (f) history mencatat flag (setelah update ber-flag).
select supabase_tests.check('history mencatat flag mock',
  exists (select 1 from public.user_location_history
          where user_id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mocked = true));

-- (b) akurasi 0 → accuracy_zero.
select public.update_my_location(-6.2001, 106.8001, 'gps', null, false, 0);
select supabase_tests.check('accuracy 0 → accuracy_zero',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mock_reason like '%accuracy_zero%'));

-- (c) lompatan jauh setelah ≥10 dtk → impossible_speed.
--     (Seed titik lama ber-timestamp 60 dtk lalu agar jeda memenuhi syarat.)
delete from public.user_location_history
 where user_id = 'd0c1e000-0000-4000-8000-000000000031';
insert into public.user_location_history (user_id, lat, lon, loc_source, created_at)
values ('d0c1e000-0000-4000-8000-000000000031', -6.2, 106.8, 'gps', now() - interval '60 seconds');
select public.update_my_location(40.0, -3.0, 'gps', null, false, 20);
select supabase_tests.check('lompatan mustahil → impossible_speed',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mock_reason like '%impossible_speed%'));

-- (d) GPS vs IP beda jauh → spoof_delta.
update public.profiles set lat_ip = -6.2, lon_ip = 106.8, ip_updated_at = now()
 where id = 'd0c1e000-0000-4000-8000-000000000031';
select public.update_my_location(-8.65, 115.21, 'gps', null, false, 20);
select supabase_tests.check('gps jauh dari ip → spoof_delta',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mock_reason like '%spoof_delta%'));

-- (e) update normal (dekat, akurasi wajar) → TIDAK ditandai.
delete from public.user_location_history
 where user_id = 'd0c1e000-0000-4000-8000-000000000031';
insert into public.user_location_history (user_id, lat, lon, loc_source, created_at)
values ('d0c1e000-0000-4000-8000-000000000031', -8.65, 115.21, 'gps', now() - interval '60 seconds');
update public.profiles set lat_ip = -8.65, lon_ip = 115.21
 where id = 'd0c1e000-0000-4000-8000-000000000031';
select public.update_my_location(-8.6501, 115.2101, 'gps', null, false, 30);
select supabase_tests.check('normal → tidak ditandai',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mocked = false
            and location_mock_reason is null));

-- (f) lihat: check flag history di atas (setelah step a).

-- (g) source ip tak dinilai (tak menandai).
select public.update_my_location(-6.2, 106.8, 'ip', '1.2.3.4', false, null);
select supabase_tests.check('source ip tak menjadi flag',
  (select location_mocked from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000031') = false);

select supabase_tests.report() as result;
rollback;
