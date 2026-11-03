-- Lapis 3: KYC validasi server (20261109010000).
--   K1: kyc_nik_info — struktur NIK (provinsi, tgl, gender, urut).
--   K2: submit_kyc — kode error KYC_*, NIK unik antar akun, simpan checks.
--   K3: admin_kyc_review — lock + wajib pending + alasan tolak.
--   K4: admin_kyc_list tanpa foto; admin_kyc_photos hanya admin.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed090000-0000-4000-8000-0000000000f1'::uuid, '[TEST] KYC-F1', 'online');
select supabase_tests.mk_dummy('ed090000-0000-4000-8000-0000000000f2'::uuid, '[TEST] KYC-F2', 'online');
update public.profiles set gender = 'female'
 where id in ('ed090000-0000-4000-8000-0000000000f1',
              'ed090000-0000-4000-8000-0000000000f2');

create temp table _k (k text primary key, ok boolean, msg text) on commit drop;
grant all on _k to service_role;

-- ════ K1. Struktur NIK ════
select supabase_tests.check('KYC: NIK perempuan valid → tgl 1998-08-05, female',
  public.kyc_nik_info('3273054508980001') =
    jsonb_build_object('birth_date', '1998-08-05'::date, 'female', true));
select supabase_tests.check('KYC: NIK laki-laki → female=false',
  (public.kyc_nik_info('3171021203050002')->>'female')::boolean = false);
select supabase_tests.check('KYC: provinsi 99 → null',
  public.kyc_nik_info('9973054508980001') is null);
select supabase_tests.check('KYC: 31 Februari → null',
  public.kyc_nik_info('3273057102980001') is null);
select supabase_tests.check('KYC: urut 0000 → null',
  public.kyc_nik_info('3273054508980000') is null);
select supabase_tests.check('KYC: bukan 16 digit → null',
  public.kyc_nik_info('32730545089800') is null);

-- Helper: panggil submit_kyc sebagai uid tertentu, tangkap pesan error.
create or replace function pg_temp.try_submit(
  p_uid uuid, p_nik text, p_birth date, p_type text default 'ktp')
returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform public.submit_kyc('[TEST] SITI AMINAH', p_type, p_nik,
    'data:image/jpeg;base64,' || repeat('A', 120),
    'data:image/jpeg;base64,' || repeat('B', 120),
    p_birth, '{"live": true, "v": 1}'::jsonb);
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

-- ════ K2. submit_kyc ════
select supabase_tests.check('KYC: dokumen selain KTP → KYC_DOC_TYPE',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f1',
    '3273054508980001', '1998-08-05', 'passport') like '%KYC_DOC_TYPE%');
select supabase_tests.check('KYC: NIK karangan → KYC_NIK_INVALID',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f1',
    '1234567890123456', '1998-08-05') like '%KYC_NIK_INVALID%');
select supabase_tests.check('KYC: tgl lahir ≠ NIK → KYC_BIRTH_MISMATCH',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f1',
    '3273054508980001', '1998-08-06') like '%KYC_BIRTH_MISMATCH%');
select supabase_tests.check('KYC: lahir 2015 → KYC_UNDERAGE',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f1',
    '3273054508150001', '2015-08-05') like '%KYC_UNDERAGE%');
select supabase_tests.check('KYC: data valid → ok',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f1',
    '3273054508980001', '1998-08-05') = 'ok');
select supabase_tests.check('KYC: checks klien & server_checks tersimpan',
  exists (select 1 from public.kyc_requests
          where user_id = 'ed090000-0000-4000-8000-0000000000f1'
            and status = 'pending'
            and (checks->>'live')::boolean = true
            and (server_checks->>'nik_female')::boolean = true
            and (server_checks->>'gender_match_profile')::boolean = true));
select supabase_tests.check('KYC: submit ulang saat pending → KYC_ALREADY_SUBMITTED',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f1',
    '3273054508980001', '1998-08-05') like '%KYC_ALREADY_SUBMITTED%');
select supabase_tests.check('KYC: NIK sama di akun lain → KYC_NIK_USED',
  pg_temp.try_submit('ed090000-0000-4000-8000-0000000000f2',
    '3273054508980001', '1998-08-05') like '%KYC_NIK_USED%');

-- ════ K3. Review admin ════
select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
select set_config('request.jwt.claim.sub', '', true);

do $$
declare v_id uuid; v_msg text;
begin
  select id into v_id from public.kyc_requests
   where user_id = 'ed090000-0000-4000-8000-0000000000f1' and status = 'pending';
  begin
    perform public.admin_kyc_review(v_id, false, '   ');
    v_msg := 'no exception';
  exception when others then
    v_msg := sqlerrm;
  end;
  insert into _k values ('rj_noreason', v_msg like '%Reason required%', v_msg);
  insert into _k values ('ap1', (public.admin_kyc_review(v_id, true)->>'ok')::boolean,
                         'approve');
  insert into _k values ('ap2',
    public.admin_kyc_review(v_id, false, 'x')->>'error' = 'ALREADY_PROCESSED',
    'second');
end $$;
select supabase_tests.check('KYC: tolak tanpa alasan → error',
  (select ok from _k where k='rj_noreason'), (select msg from _k where k='rj_noreason'));
select supabase_tests.check('KYC: approve pending → ok',
  (select ok from _k where k='ap1'));
select supabase_tests.check('KYC: proses ulang → ALREADY_PROCESSED (tak menimpa)',
  (select ok from _k where k='ap2')
  and exists (select 1 from public.kyc_requests
              where user_id = 'ed090000-0000-4000-8000-0000000000f1'
                and status = 'approved'));

-- ════ K4. Daftar admin tanpa foto ════
select supabase_tests.check('KYC: admin_kyc_list tanpa id_photo/selfie_photo',
  not exists (
    select 1 from jsonb_array_elements(public.admin_kyc_list('all')) e
     where e ? 'id_photo' or e ? 'selfie_photo'));
select supabase_tests.check('KYC: admin_kyc_photos mengembalikan foto',
  length(public.admin_kyc_photos(
    (select id from public.kyc_requests
      where user_id = 'ed090000-0000-4000-8000-0000000000f1'))->>'id_photo') > 100);
select supabase_tests.check('KYC: admin_kyc_photos tidak executable anon',
  has_function_privilege('anon', 'public.admin_kyc_photos(uuid)', 'execute') = false);
select supabase_tests.check('KYC: submit_kyc v2 tidak executable anon',
  has_function_privilege('anon',
    'public.submit_kyc(text,text,text,text,text,date,jsonb)', 'execute') = false);

select set_config('request.jwt.claim.email', '', true);
select supabase_tests.report() as result;
rollback;
