-- Lapis 3: arsip device + GPS user terhapus tetap tampil di admin Terhapus.
-- Insiden: delete_my_account & admin_delete_anon_user menghapus eksplisit
-- user_devices + user_location_history (wajib, kalau tidak 23502) sehingga
-- admin_deleted_device_history selalu kosong & GPS tak ada RPC-nya.
-- Fix 20260926000000: snapshot ke deleted_users.devices/locations saat archive.
-- Transaksional (BEGIN/ROLLBACK), tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('deleted_users punya kolom devices',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'deleted_users'
      and column_name = 'devices'
  ));

select supabase_tests.check('deleted_users punya kolom locations',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'deleted_users'
      and column_name = 'locations'
  ));

select supabase_tests.check('fn_archive_deleted_user snapshot devices',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_archive_deleted_user'
      and pg_get_functiondef(p.oid) like '%user_devices%'
      and pg_get_functiondef(p.oid) like '%v_devices%'
  ));

select supabase_tests.check('fn_archive_deleted_user snapshot locations',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_archive_deleted_user'
      and pg_get_functiondef(p.oid) like '%user_location_history%'
      and pg_get_functiondef(p.oid) like '%v_locations%'
  ));

select supabase_tests.check('admin_deleted_device_history baca arsip dulu',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_deleted_device_history'
      and pg_get_functiondef(p.oid) like '%deleted_users%'
  ));

select supabase_tests.check('admin_deleted_location_history ada',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_deleted_location_history'
  ));

select supabase_tests.check('admin_list_deleted sertakan device_count/location_count',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_list_deleted'
      and pg_get_functiondef(p.oid) like '%device_count%'
      and pg_get_functiondef(p.oid) like '%location_count%'
  ));

select supabase_tests.check('delete_my_account tetap hapus live devices/location (deletion sukses)',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_my_account'
      and pg_get_functiondef(p.oid)
        like '%delete from public.user_devices where user_id = v_uid%'
  ));

select supabase_tests.report() as result;
rollback;
