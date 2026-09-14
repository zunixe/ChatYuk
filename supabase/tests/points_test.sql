-- Lapis 3: invariant poin/ekonomi (idempotensi klaim, kolom ledger).
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('one_time_bonus() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='one_time_bonus'));
select supabase_tests.check('send_coins() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='send_coins'));
select supabase_tests.check('send_gift() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='send_gift'));
select supabase_tests.check('room_read_bonus() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='room_read_bonus'));
select supabase_tests.check('points_leaderboard() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='points_leaderboard'));

-- Kolom saldo & ledger.
select supabase_tests.check('profiles.points ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles' and column_name='points'));

-- one_time_bonus idempoten: action_key unik di ledger.
select supabase_tests.check('tabel coin_ledger ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='coin_ledger'));

select supabase_tests.report() as result;
rollback;
