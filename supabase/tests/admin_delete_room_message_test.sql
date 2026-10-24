-- pgTAP: RPC admin hapus pesan room (siapa pun).
-- Fungsi ada, SECURITY DEFINER, gate email admin, dan user biasa ditolak.
-- Transaksional (BEGIN/ROLLBACK), tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- Fungsi terpasang.
select supabase_tests.check('admin_delete_room_message terpasang',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_delete_room_message'
  ));

-- SECURITY DEFINER (agar bisa update pesan user lain, tetap digerbang email).
select supabase_tests.check('admin_delete_room_message security definer',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_delete_room_message'
      and p.prosecdef = true
  ));

-- Gate email admin tertanam di body.
select supabase_tests.check('admin_delete_room_message cek email admin',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_delete_room_message'
      and pg_get_functiondef(p.oid) like '%zunixe@gmail.com%'
  ));

-- anon tidak boleh EXECUTE (hanya authenticated/service_role).
select supabase_tests.check('admin_delete_room_message: anon tidak boleh execute',
  not has_function_privilege('anon',
    'public.admin_delete_room_message(bigint,boolean)', 'execute'));

select supabase_tests.report() as result;
rollback;
