-- Lapis 3: notif "X online" → teman + follower + pernah chat — 20260930052500.
-- Jalankan: scripts/run_sql_tests.sh online_notify_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback). Outbox yang
-- ditulis trigger ikut rollback → tidak ada push sungguhan terkirim.
-- Aturan: penerima = UNION(teman mutual | follower-ku | pernah 1:1 chat),
--   kecuali author, kecuali blokir dua arah, kecuali author dummy.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000022'::uuid, 'TEST Friend');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000023'::uuid, 'TEST Follower');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000024'::uuid, 'TEST Chatter');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000025'::uuid, 'TEST Stranger');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000026'::uuid, 'TEST Blocked');

-- Owner BUKAN dummy (dummy tak me-notify — guard trigger): buat manual.
insert into auth.users (id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at, created_at, updated_at)
values ('d0c1e000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000000',
  'authenticated', 'authenticated', 'owner21@test.local', '', now(), now(), now())
on conflict (id) do nothing;
insert into public.profiles (id, nickname, gender, age, country, city,
  status, last_seen, is_registered, login_at, created_at)
values ('d0c1e000-0000-4000-8000-000000000021', 'TEST OnlineOwn', 'male', 25,
  'ID', 'Jakarta', 'offline', now(), true, now(), now())
on conflict (id) do update
  set nickname = 'TEST OnlineOwn', status = 'offline';
delete from public.dummy_accounts
 where uid = 'd0c1e000-0000-4000-8000-000000000021';

-- Token palsu per penerima (outbox hanya ditulis bila ada token).
insert into public.user_devices (user_id, install_id, fcm_token) values
 ('d0c1e000-0000-4000-8000-000000000022', 'test-22', 'TOK22'),
 ('d0c1e000-0000-4000-8000-000000000023', 'test-23', 'TOK23'),
 ('d0c1e000-0000-4000-8000-000000000024', 'test-24', 'TOK24'),
 ('d0c1e000-0000-4000-8000-000000000025', 'test-25', 'TOK25'),
 ('d0c1e000-0000-4000-8000-000000000026', 'test-26', 'TOK26');

-- Teman = mutual follow owner<->22.
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000021', 'd0c1e000-0000-4000-8000-000000000022'),
 ('d0c1e000-0000-4000-8000-000000000022', 'd0c1e000-0000-4000-8000-000000000021');
-- Follower searah: 23 follow owner.
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000023', 'd0c1e000-0000-4000-8000-000000000021');
-- Pernah chat: owner<->24.
insert into public.private_chats (chat_id, participants) values
 ('test-online-24', array['d0c1e000-0000-4000-8000-000000000021','d0c1e000-0000-4000-8000-000000000024']::uuid[]);
-- Owner memblokir 26.
insert into public.blocks (blocker_id, blocked_id) values
 ('d0c1e000-0000-4000-8000-000000000021', 'd0c1e000-0000-4000-8000-000000000026');

-- Picu transisi offline → online.
update public.profiles set status = 'online'
 where id = 'd0c1e000-0000-4000-8000-000000000021';

select supabase_tests.check('teman dapat notif online',
  exists (select 1 from public.outbox
          where payload->>'token' = 'TOK22'
            and payload->'data'->>'type' = 'online'
            and payload->'data'->>'otherUid' = 'd0c1e000-0000-4000-8000-000000000021'));
select supabase_tests.check('follower dapat notif online',
  exists (select 1 from public.outbox
          where payload->>'token' = 'TOK23'
            and payload->'data'->>'type' = 'online'));
select supabase_tests.check('pernah-chat dapat notif online + chatId',
  exists (select 1 from public.outbox
          where payload->>'token' = 'TOK24'
            and payload->'data'->>'chatId' = 'test-online-24'));
select supabase_tests.check('stranger TIDAK dapat notif',
  not exists (select 1 from public.outbox
              where payload->>'token' = 'TOK25'));
select supabase_tests.check('yang diblokir TIDAK dapat notif',
  not exists (select 1 from public.outbox
              where payload->>'token' = 'TOK26'));

-- Transisi online → online lagi = tidak notify ulang.
delete from public.outbox where payload->>'token' like 'TOK2%';
update public.profiles set status = 'idle'
 where id = 'd0c1e000-0000-4000-8000-000000000021';
delete from public.outbox where payload->>'token' like 'TOK2%';
update public.profiles set status = 'online'
 where id = 'd0c1e000-0000-4000-8000-000000000021';
select supabase_tests.check('idle → online notify lagi',
  exists (select 1 from public.outbox
          where payload->>'token' = 'TOK22'));

select supabase_tests.report() as result;
rollback;
