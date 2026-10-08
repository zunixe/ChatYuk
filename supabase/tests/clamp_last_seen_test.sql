-- Lapis 3: clamp last_seen (fix "online terus" akibat clock skew HP) — 20261009120000.
-- Jalankan: scripts/run_sql_tests.sh clamp_last_seen_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000051'::uuid, 'TEST ClampUser', 'online');

-- (a) set last_seen 5 jam ke DEPAN → WAJIB ter-clamp ke now() (tidak masa depan).
update public.profiles
   set last_seen = now() + interval '5 hours'
 where id = 'd0c1e000-0000-4000-8000-000000000051';
select supabase_tests.check('last_seen masa depan → ter-clamp (tidak > now())',
  (select last_seen <= now() from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000051'));

-- (b) last_seen lampau tetap dibiarkan (tidak dimajukan).
update public.profiles
   set last_seen = now() - interval '2 hours'
 where id = 'd0c1e000-0000-4000-8000-000000000051';
select supabase_tests.check('last_seen lampau tetap apa adanya',
  (select last_seen <= now() - interval '1 hour' from public.profiles
    where id = 'd0c1e000-0000-4000-8000-000000000051'));

-- (c) trigger terpasang di tabel profiles.
select supabase_tests.check('trigger trg_clamp_last_seen terpasang',
  exists (select 1 from pg_trigger
           where tgrelid = 'public.profiles'::regclass
             and tgname = 'trg_clamp_last_seen'));

select supabase_tests.report() as result;
rollback;
