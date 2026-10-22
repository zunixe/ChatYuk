-- Lapis 3: app_settings.app_shared_secret TIDAK terbaca klien (20261022120000),
-- tapi kolom yang dibaca klien tetap terbaca (popup update, insiden 2026-09-22).
-- Jalankan: scripts/run_sql_tests.sh app_settings_secret_test.sql
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('app_shared_secret tanpa SELECT (anon+authenticated)',
  not has_column_privilege('anon', 'public.app_settings', 'app_shared_secret', 'SELECT')
  and not has_column_privilege('authenticated', 'public.app_settings', 'app_shared_secret', 'SELECT'));

select supabase_tests.check('tidak ada GRANT SELECT level tabel app_settings',
  not has_table_privilege('anon', 'public.app_settings', 'SELECT')
  and not has_table_privilege('authenticated', 'public.app_settings', 'SELECT'));

select supabase_tests.check('kolom update & setting global terbaca (anon+authenticated)',
  (select bool_and(has_column_privilege(r, 'public.app_settings', c, 'SELECT'))
   from (values ('anon'), ('authenticated')) as rr(r),
        (values ('id'), ('update_enabled'), ('latest_version'), ('min_version'),
                ('screenshot_enabled'), ('ai_global_enabled')) as t(c)));

select supabase_tests.report() as result;
rollback;
