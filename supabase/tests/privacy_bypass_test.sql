-- Lapis 3: bypass privasi admin (toggle Global Setting).
-- Jalankan: scripts/run_sql_tests.sh privacy_bypass_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
-- Aturan: flag ON saja TIDAK cukup — pemanggil harus email admin.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('aa000000-0000-0000-0000-00000000000a'::uuid, 'TEST Own');
select supabase_tests.mk_dummy('cc000000-0000-0000-0000-00000000000c'::uuid, 'TEST Stranger');

-- Owner kunci rapat: about = nobody.
update public.profiles set about_visibility = 'nobody'
 where id = 'aa000000-0000-0000-0000-00000000000a';

-- Konteks pemanggil: user biasa.
select set_config('request.jwt.claims',
  '{"sub":"cc000000-0000-0000-0000-00000000000c","email":"user@contoh.id","role":"authenticated"}', false);

select supabase_tests.check('baseline: non-teman ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- Flag ON tapi pemanggil BUKAN admin → tetap ditolak.
update public.app_settings set privacy_bypass_enabled = true where id = 'global';
select supabase_tests.check('flag ON + pemanggil biasa → tetap ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- Konteks pemanggil: admin.
select set_config('request.jwt.claims',
  '{"email":"zunixe@gmail.com","role":"authenticated"}', false);

select supabase_tests.check('flag ON + pemanggil admin → boleh',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- Flag OFF + pemanggil admin → tetap ditolak (default aman).
update public.app_settings set privacy_bypass_enabled = false where id = 'global';
select supabase_tests.check('flag OFF + pemanggil admin → tetap ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- Setter non-admin: harus melempar Unauthorized (flag tetap false).
select set_config('request.jwt.claims',
  '{"sub":"cc000000-0000-0000-0000-00000000000c","email":"user@contoh.id","role":"authenticated"}', false);
DO $$
begin
  perform public.admin_set_privacy_bypass(true);
exception when others then
  null; -- diharapkan: Unauthorized
end $$;
select supabase_tests.check('setter non-admin → flag tetap false',
  (select privacy_bypass_enabled from public.app_settings where id = 'global') = false);

-- Setter: admin boleh.
select set_config('request.jwt.claims',
  '{"email":"zunixe@gmail.com","role":"authenticated"}', false);
select supabase_tests.check('admin_set_privacy_bypass admin → flag true',
  ((select public.admin_set_privacy_bypass(true))->>'privacy_bypass_enabled')::boolean);
select supabase_tests.check('admin_set_privacy_bypass admin → flag false',
  ((select public.admin_set_privacy_bypass(false))->>'privacy_bypass_enabled')::boolean = false);

select supabase_tests.report() as result;
rollback;
