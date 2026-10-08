-- Lapis 3: presence stale offline + clamp kuat (fix "online terus") — 20261009130000.
-- Jalankan: scripts/run_sql_tests.sh presence_stale_offline_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000061'::uuid, 'TEST StaleUser', 'online');

-- (a) last_seen masa depan → di-clamp DAN status dipaksa offline.
update public.profiles
   set last_seen = now() + interval '5 hours'
 where id = 'd0c1e000-0000-4000-8000-000000000061';
select supabase_tests.check('last_seen masa depan → clamp + status offline',
  (select status = 'offline' and last_seen <= now()
     from public.profiles where id = 'd0c1e000-0000-4000-8000-000000000061'));

-- (b) status online + last_seen basi (>30 mnt) → presence_stale_offline set offline.
update public.profiles
   set status = 'online', last_seen = now() - interval '2 hours'
 where id = 'd0c1e000-0000-4000-8000-000000000061';
select public.presence_stale_offline(30);
select supabase_tests.check('basi >30m → offline',
  (select status = 'offline'
     from public.profiles where id = 'd0c1e000-0000-4000-8000-000000000061'));

-- (c) status online + last_seen SEGAR (<30 mnt) → TIDAK disentuh.
update public.profiles
   set status = 'online', last_seen = now() - interval '2 minutes'
 where id = 'd0c1e000-0000-4000-8000-000000000061';
select public.presence_stale_offline(30);
select supabase_tests.check('segar <30m → tetap online',
  (select status = 'online'
     from public.profiles where id = 'd0c1e000-0000-4000-8000-000000000061'));

-- (d) housekeeping_tick memanggil presence_stale_offline (regresi guard).
select supabase_tests.check('housekeeping_tick panggil presence_stale_offline',
  (select prosrc ilike '%presence_stale_offline%'
     from pg_proc where proname = 'housekeeping_tick'));

select supabase_tests.report() as result;
rollback;
