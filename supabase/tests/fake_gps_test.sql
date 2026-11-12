-- Lapis 3: deteksi Fake GPS (flag + heuristik) — 20261002060000.
-- Jalankan: scripts/run_sql_tests.sh fake_gps_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
-- Aturan (20261111140000): HARD = is_mocked | accuracy_zero | known_emulator |
--   impossible_speed → cukup 1. SOFT = spoof_delta | static_coord |
--   shared_coord → butuh ≥2 (orang serumah/sekantor TIDAK ditandai).
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

-- (d) GPS vs IP beda jauh (soft) SENDIRIAN → TIDAK ditandai.
delete from public.user_location_history
 where user_id = 'd0c1e000-0000-4000-8000-000000000031';
update public.profiles set lat_ip = -6.2, lon_ip = 106.8, ip_updated_at = now()
 where id = 'd0c1e000-0000-4000-8000-000000000031';
select public.update_my_location(-2.53, 140.7, 'gps', null, false, 20);
select supabase_tests.check('spoof_delta sendirian → tidak ditandai',
  (select location_mocked from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000031') = false);

-- (d2) spoof_delta + shared_coord (2 soft) → ditandai.
select supabase_tests.mk_dummy(('d0c1e000-0000-4000-8000-00000000004' || g)::uuid,
                               'TEST Shared ' || g, 'online')
  from generate_series(1, 3) g;
delete from public.dummy_accounts
 where uid::text like 'd0c1e000-0000-4000-8000-00000000004%';
update public.profiles
   set lat_gps = -2.53, lon_gps = 140.7, gps_updated_at = now(),
       location_accuracy_m = 12
 where id::text like 'd0c1e000-0000-4000-8000-00000000004%';
select public.update_my_location(-2.53, 140.7, 'gps', null, false, 15);
select supabase_tests.check('spoof_delta + shared_coord → ditandai',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mocked = true
            and location_mock_reason like '%spoof_delta%'
            and location_mock_reason like '%shared_coord%'));

-- (d3) serumah (3 user lain di titik sama) tanpa sinyal lain → TIDAK.
update public.profiles set lat_ip = -2.53, lon_ip = 140.7
 where id = 'd0c1e000-0000-4000-8000-000000000031';
select public.update_my_location(-2.53, 140.7, 'gps', null, false, 15);
select supabase_tests.check('shared_coord sendirian (serumah) → tidak ditandai',
  (select location_mocked from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000031') = false);

-- (d4) diam di rumah dgn fix kasar (akurasi 2000 m, identik) → TIDAK.
delete from public.user_location_history
 where user_id = 'd0c1e000-0000-4000-8000-000000000031';
insert into public.user_location_history (user_id, lat, lon, loc_source, accuracy_m, created_at)
select 'd0c1e000-0000-4000-8000-000000000031', -2.6, 140.6, 'gps', 2000,
       now() - (g || ' hours')::interval
  from generate_series(1, 6) g;
select public.update_my_location(-2.6, 140.6, 'gps', null, false, 2000);
select supabase_tests.check('static fix kasar → tidak ditandai',
  (select location_mocked from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000031') = false);

-- (d5) lompatan fix kasar (cell tower, 3 km dlm 40 dtk) → bukan impossible_speed.
delete from public.user_location_history
 where user_id = 'd0c1e000-0000-4000-8000-000000000031';
insert into public.user_location_history (user_id, lat, lon, loc_source, accuracy_m, created_at)
values ('d0c1e000-0000-4000-8000-000000000031', -2.6, 140.6, 'gps', 1500, now() - interval '40 seconds');
select public.update_my_location(-2.627, 140.6, 'gps', null, false, 1500);
select supabase_tests.check('lompatan fix kasar → tidak ditandai',
  (select location_mocked from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000031') = false);

-- (d6) default emulator (hard) → ditandai.
select public.update_my_location(37.4220, -122.0841, 'gps', null, false, 5);
select supabase_tests.check('known_emulator → ditandai',
  exists (select 1 from public.profiles
          where id = 'd0c1e000-0000-4000-8000-000000000031'
            and location_mocked = true
            and location_mock_reason like '%known_emulator%'));

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
