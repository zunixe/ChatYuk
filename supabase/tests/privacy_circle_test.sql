-- Lapis 3: privasi mode "circle" (Kenalan) — 20260929120000.
-- Jalankan: scripts/run_sql_tests.sh privacy_circle_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
-- Aturan: lolos = teman | follower-ku | subscriber-ku AKTIF | pernah chat
--   (termasuk anon). Ditolak = stranger | subscriber kedaluwarsa |
--   following-ku yang tak follback. Tanpa circle_except (daftar kecuali
--   diabaikan, konsisten 'friends').
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000001'::uuid, 'TEST CircleOwn', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000002'::uuid, 'TEST Friend');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000003'::uuid, 'TEST Follower');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000004'::uuid, 'TEST Following');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000005'::uuid, 'TEST SubActive');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000006'::uuid, 'TEST SubExpired');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000007'::uuid, 'TEST Chatter');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000008'::uuid, 'TEST AnonChatter');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000009'::uuid, 'TEST Stranger');

-- Anon: gate buta registered/anon, tapi simulasikan dengan jujur.
update public.profiles set is_registered = false
 where id = 'd0c1e000-0000-4000-8000-000000000008';

-- Relasi terhadap owner (...001).
-- Teman = mutual follow.
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000002'),
 ('d0c1e000-0000-4000-8000-000000000002', 'd0c1e000-0000-4000-8000-000000000001');
-- Follower searah (dia follow owner).
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000003', 'd0c1e000-0000-4000-8000-000000000001');
-- Following searah (owner follow dia, tak difollback).
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000004');
-- Subscriber aktif + kedaluwarsa.
insert into public.subscriptions (subscriber_id, creator_id, price, expires_at) values
 ('d0c1e000-0000-4000-8000-000000000005', 'd0c1e000-0000-4000-8000-000000000001', 1, now() + interval '30 days'),
 ('d0c1e000-0000-4000-8000-000000000006', 'd0c1e000-0000-4000-8000-000000000001', 1, now() - interval '1 day');
-- Pernah chat (registered + anon).
insert into public.private_chats (chat_id, participants) values
 ('test-circle-7', array['d0c1e000-0000-4000-8000-000000000001','d0c1e000-0000-4000-8000-000000000007']::uuid[]),
 ('test-circle-8', array['d0c1e000-0000-4000-8000-000000000001','d0c1e000-0000-4000-8000-000000000008']::uuid[]);

-- Owner kunci: foto + presence = circle. Avatar diisi agar cermin
-- photo_ok terbukti (mask = '' vs lolos = isi).
update public.profiles
   set profile_photo_visibility = 'circle', presence_visibility = 'circle',
       avatar = 'TESTAVATAR'
 where id = 'd0c1e000-0000-4000-8000-000000000001';

select supabase_tests.check('self selalu lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000001'));
select supabase_tests.check('teman (mutual) lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000002'));
select supabase_tests.check('follower searah lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000003'));
select supabase_tests.check('following searah (tak difollback) ditolak',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000004'));
select supabase_tests.check('subscriber aktif lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000005'));
select supabase_tests.check('subscriber kedaluwarsa ditolak',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000006'));
select supabase_tests.check('pernah chat (bukan teman) lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000007'));
select supabase_tests.check('anon pernah chat lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000008'));
select supabase_tests.check('stranger ditolak',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000009'));
select supabase_tests.check('berlaku per-field (presence)',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','presence',
    'd0c1e000-0000-4000-8000-000000000003'));

-- Tanpa circle_except: teman di daftar kecuali TETAP lolos di mode circle.
insert into public.profile_privacy_exclusions (owner_id, excluded_uid, field) values
 ('d0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000002', 'profile_photo');
select supabase_tests.check('daftar kecuali diabaikan di mode circle',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','profile_photo',
    'd0c1e000-0000-4000-8000-000000000002'));

-- Cabang lama utuh: mode friends tetap menolak follower non-mutual.
update public.profiles set presence_visibility = 'friends'
 where id = 'd0c1e000-0000-4000-8000-000000000001';
select supabase_tests.check('friends: follower non-mutual tetap ditolak',
  not public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','presence',
    'd0c1e000-0000-4000-8000-000000000003'));
select supabase_tests.check('friends: mutual tetap lolos',
  public.privacy_can_view('d0c1e000-0000-4000-8000-000000000001','presence',
    'd0c1e000-0000-4000-8000-000000000002'));
update public.profiles set presence_visibility = 'circle'
 where id = 'd0c1e000-0000-4000-8000-000000000001';

-- Cermin get_online_users: follower melihat baris owner UTUH (tampil+isi),
-- stranger melihat baris yang DISENSOR (tampil, status offline, avatar '').
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000003","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('ctx follower terbaca',
  auth.uid() = 'd0c1e000-0000-4000-8000-000000000003');
select supabase_tests.check('cermin: follower lihat owner utuh',
  exists (select 1 from jsonb_array_elements(public.get_online_users(null, 1000)) r
           where r->>'nickname' = 'TEST CircleOwn'
             and r->>'status' = 'online' and r->>'avatar' = 'TESTAVATAR'));
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000009","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('cermin: stranger tidak melihat owner di online list (konsisten semua mode)',
  not exists (select 1 from jsonb_array_elements(public.get_online_users(null, 1000)) r
           where r->>'nickname' = 'TEST CircleOwn'));
select supabase_tests.check('tampil+sensor: presence_for stranger tetap tampil tersensor',
  exists (select 1 from jsonb_array_elements(
            public.presence_for(array['d0c1e000-0000-4000-8000-000000000001']::uuid[])) r
           where r->>'nickname' = 'TEST CircleOwn'
             and r->>'status' = 'offline' and (r->>'avatar') = ''));

select supabase_tests.report() as result;
rollback;
