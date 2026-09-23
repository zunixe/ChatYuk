-- Lapis 3: hapus akun tidak boleh 23502 (insiden anon "hdjdjfj" 2026-09-23).
-- FK user_devices.user_id & user_location_history.user_id = SET NULL on
-- delete, TAPI kolomnya NOT NULL → `delete from profiles` selalu meledak
-- (null value in column "user_id") begitu user punya device row, yaitu
-- hampir semua user nyata. Fix: hapus eksplisit keduanya SEBELUM profiles.
-- Transaksional (BEGIN/ROLLBACK), tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('delete_my_account hapus user_devices eksplisit',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_my_account'
      and pg_get_functiondef(p.oid)
        like '%delete from public.user_devices where user_id = v_uid%'
  ));

select supabase_tests.check('delete_my_account hapus user_location_history eksplisit',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_my_account'
      and pg_get_functiondef(p.oid)
        like '%delete from public.user_location_history where user_id = v_uid%'
  ));

select supabase_tests.check('hapus device/location SEBELUM hapus profiles (urutan)',
  (select strpos(def, 'delete from public.user_devices')
            < strpos(def, 'delete from public.profiles')
    from (select pg_get_functiondef(p.oid) as def
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'delete_my_account'
          limit 1) s));

select supabase_tests.check('komentar usang "FK SET NULL" sudah dikoreksi',
  not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_my_account'
      and pg_get_functiondef(p.oid) like '%FK SET NULL%'
  ));

select supabase_tests.report() as result;
rollback;
