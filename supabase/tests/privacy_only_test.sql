-- Lapis 3: privasi mode "only" (Hanya orang tertentu) — 20260929130000.
-- Jalankan: scripts/run_sql_tests.sh privacy_only_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
-- Aturan: 'only' = daftar PUTIH. Lolos HANYA bila viewer ada di
--   profile_privacy_exclusions(owner, field, viewer). Teman/follower/
--   subscriber TIDAK otomatis lolos (beda dari 'circle' lama).
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000001'::uuid, 'TEST OnlyOwn', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000002'::uuid, 'TEST Friend');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000003'::uuid, 'TEST Stranger');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000004'::uuid, 'TEST Other');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000005'::uuid, 'TEST Isolated');

-- Relasi terhadap owner (...001): teman (mutual follow) — TIDAK cukup di 'only'.
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000002'),
 ('d0c1e000-0000-4000-8000-000000000002', 'd0c1e000-0000-4000-8000-000000000001');

-- Owner kunci: foto + presence = only. Avatar diisi agar cermin
-- photo_ok terbukti (mask = '' vs lolos = isi).
update public.profiles
   set profile_photo_visibility = 'only', presence_visibility = 'only',
       about_visibility = 'only',
       avatar = 'TESTAVATAR'
 where id = 'd0c1e000-0000-4000-8000-000000000001';

-- Daftar putih per-field: hanya stranger (...003) yang dipilih.
insert into public.profile_privacy_exclusions (owner_id, excluded_uid, field) values
 ('d0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000003', 'profile_photo'),
 ('d0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000003', 'presence');

select supabase_tests.check('self selalu lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000001'));
select supabase_tests.check('orang di daftar putih lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000003'));
select supabase_tests.check('teman TIDAK otomatis lolos di only',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000002'));
select supabase_tests.check('stranger lain ditolak',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000004'));
select supabase_tests.check('berlaku per-field (presence)',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','presence',
    'd0c1e000-0000-4000-8000-000000000003'));
select supabase_tests.check('field tanpa daftar putih → tak ada yang lolos',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','about',
    'd0c1e000-0000-4000-8000-000000000003'));

-- Cabang lama utuh: mode friends tetap menolak non-teman.
update public.profiles set presence_visibility = 'friends'
 where id = 'd0c1e000-0000-4000-8000-000000000001';
select supabase_tests.check('friends: non-teman tetap ditolak',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','presence',
    'd0c1e000-0000-4000-8000-000000000003'));
select supabase_tests.check('friends: mutual tetap lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','presence',
    'd0c1e000-0000-4000-8000-000000000002'));

update public.profiles set presence_visibility = 'only'
 where id = 'd0c1e000-0000-4000-8000-000000000001';

-- update_privacy_settings: allowlist 6 nilai + guard 'only' tanpa daftar.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000001","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('ctx owner terbaca',
  auth.uid() = 'd0c1e000-0000-4000-8000-000000000001');
-- Simpan 'only' untuk field TANPA daftar (story) harus GAGAL.
do $$
begin
  begin
    perform public.update_privacy_settings(null, null, null, null, 'only', null);
    perform set_config('supabase_tests.only_guard', 'no_raise', true);
  exception when others then
    perform set_config('supabase_tests.only_guard', 'raised', true);
  end;
end $$;
select supabase_tests.check('only tanpa daftar → ditolak',
  current_setting('supabase_tests.only_guard', true) = 'raised');
-- Field ber-daftar (presence) → 'only' boleh.
select supabase_tests.check('only dengan daftar → tersimpan',
  (public.update_privacy_settings('only', null, null, null, null, null)
     ->> 'presence') = 'only');

-- Cermin get_online_users: viewer di daftar putih melihat baris owner UTUH;
-- teman (tak di daftar) TIDAK melihat owner (konsisten semua mode).
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000003","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('cermin: viewer daftar putih lihat owner utuh',
  exists (select 1 from jsonb_array_elements(public.get_online_users(null, 1000)) r
           where r->>'nickname' = 'TEST OnlyOwn'
             and r->>'status' = 'online' and r->>'avatar' = 'TESTAVATAR'));
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000002","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('cermin: teman (tak di daftar) tidak melihat owner',
  not exists (select 1 from jsonb_array_elements(public.get_online_users(null, 1000)) r
           where r->>'nickname' = 'TEST OnlyOwn'));

-- Kandidat picker: user REGISTERED yang pernah chat harus muncul (dulu
-- hanya anon yang masuk daftar → "Kartika" registered tak bisa dipilih).
insert into public.private_chats (chat_id, participants) values
 ('test-only-4', array['d0c1e000-0000-4000-8000-000000000001','d0c1e000-0000-4000-8000-000000000004']::uuid[]);
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000001","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('picker: chatter registered (bukan teman) muncul',
  exists (select 1 from jsonb_array_elements(public.privacy_excludable_users()) r
           where r->>'nickname' = 'TEST Other'));
select supabase_tests.check('picker: stranger tak pernah chat TIDAK muncul',
  not exists (select 1 from jsonb_array_elements(public.privacy_excludable_users()) r
           where r->>'nickname' = 'TEST Isolated'));

-- Mitra CHAT PRIVATE boleh lihat foto walau visibility bukan 'everyone'
-- (2026-10-05). Ditaruh PALING AKHIR agar insert private_chats tidak
-- mengganggu test picker di atas (picker = daftar chatter owner).
insert into public.private_chats (chat_id, participants) values
 ('test-only-partner', array['d0c1e000-0000-4000-8000-000000000001','d0c1e000-0000-4000-8000-000000000005']::uuid[]);
select supabase_tests.check('mitra chat private lihat foto (mode only)',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000005'));
select supabase_tests.check('mitra chat TIDAK otomatis lihat about',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','about',
    'd0c1e000-0000-4000-8000-000000000005'));

select supabase_tests.report() as result;
rollback;
