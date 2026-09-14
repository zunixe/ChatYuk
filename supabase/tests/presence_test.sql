-- Lapis 3: test invariant presence (fitur paling rawan regresi).
-- Jalankan: scripts/run_sql_tests.sh presence_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('11111111-1111-1111-1111-111111111111'::uuid, 'TEST Always');
select supabase_tests.mk_dummy('22222222-2222-2222-2222-222222222222'::uuid, 'TEST Invis', 'invisible');
select supabase_tests.mk_dummy('33333333-3333-3333-3333-333333333333'::uuid, 'TEST Wake', 'offline');
select supabase_tests.mk_dummy('44444444-4444-4444-4444-444444444444'::uuid, 'TEST Ngambek', 'online');

-- Siapkan flag.
update public.dummy_accounts set ai_always_online = true, ai_active_hours = '[]'::jsonb
 where uid = '11111111-1111-1111-1111-111111111111'::uuid;
update public.profiles set status = 'offline' where id = '11111111-1111-1111-1111-111111111111'::uuid;

update public.dummy_accounts
   set ai_always_online = false, ai_active_hours = '[]'::jsonb,
       ai_wake_until = now() + interval '1 hour'
 where uid = '33333333-3333-3333-3333-333333333333'::uuid;

update public.dummy_accounts
   set ai_always_online = false, ai_active_hours = '[]'::jsonb,
       ai_offline_until = now() + interval '1 hour'
 where uid = '44444444-4444-4444-4444-444444444444'::uuid;

select public.ai_presence_tick();

-- ── Assert ──
select supabase_tests.check('always_online → online',
  (select status from public.profiles where id='11111111-1111-1111-1111-111111111111'::uuid) = 'online');

select supabase_tests.check('invisible tidak ditimpa',
  (select status from public.profiles where id='22222222-2222-2222-2222-222222222222'::uuid) = 'invisible');

select supabase_tests.check('ai_wake_until → online',
  (select status from public.profiles where id='33333333-3333-3333-3333-333333333333'::uuid) = 'online');

select supabase_tests.check('ai_offline_until (ngambek) → offline',
  (select status from public.profiles where id='44444444-4444-4444-4444-444444444444'::uuid) = 'offline');

select supabase_tests.check('ai_presence_tick() masih ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_presence_tick'));

select supabase_tests.check('definisi memuat cabang ai_always_online',
  (select pg_get_functiondef(p.oid) like '%ai_always_online%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='ai_presence_tick'));

select supabase_tests.check('definisi memuat cabang ai_wake_until',
  (select pg_get_functiondef(p.oid) like '%ai_wake_until%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='ai_presence_tick'));

select supabase_tests.check('definisi memuat cabang invisible',
  (select pg_get_functiondef(p.oid) like '%invisible%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='ai_presence_tick'));

select supabase_tests.check('definisi memuat cabang ai_offline_until',
  (select pg_get_functiondef(p.oid) like '%ai_offline_until%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='ai_presence_tick'));

-- Ringkasan (baris terakhir = yang dibaca runner).
select supabase_tests.report() as result;
rollback;
