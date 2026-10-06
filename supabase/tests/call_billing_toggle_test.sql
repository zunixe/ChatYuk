-- Lapis 3: call_billing_tick menghormati master toggle points_enabled.
-- Melindungi: saat admin mematikan "Sistem poin", call jadi gratis total
-- (tidak ada potongan diam-diam walau flag call_billing masih published).
-- Transaksional (BEGIN/ROLLBACK) via scripts/run_sql_tests.sh.
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('call_billing_tick() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_billing_tick'));

select supabase_tests.check('call_billing_tick mengecek points_enabled',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_billing_tick'
           and p.prosrc like '%points_enabled%'));

select supabase_tests.check('jalur master-OFF gratis (per_minute 0, lanjut)',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_billing_tick'
           and p.prosrc like '%points_on is false%'
           and p.prosrc like '%''per_minute'', 0%'
           and p.prosrc like '%''can_continue'', true%'));

select supabase_tests.report() as result;
rollback;
