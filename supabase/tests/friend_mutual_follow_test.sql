-- Lapis 3: Teman = saling follow (20261027130000_friend_equals_mutual_follow).
-- Jalankan: scripts/run_sql_tests.sh friend_mutual_follow_test.sql
-- Transaksional (begin/rollback) — hanya akun dummy test, data produksi aman.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000f1'::uuid, '[TEST] FrA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000f2'::uuid, '[TEST] FrB', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000f3'::uuid, '[TEST] FrC', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000f4'::uuid, '[TEST] FrD', 'online');

create temp table _fr (k text primary key, v text) on commit drop;

-- ── 1. Follow balik manual → teman, request pending ikut accepted ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f2', true);
select public.send_friend_request('d0c1e000-0000-4000-8000-0000000000f1'); -- B minta ke A (B follow A)
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f1', true);
insert into _fr values ('follow_back', public.follow_user('d0c1e000-0000-4000-8000-0000000000f2')::text);

select supabase_tests.check('request mem-follow target (B→A ada)',
  exists(select 1 from public.follows where follower_id='d0c1e000-0000-4000-8000-0000000000f2' and followee_id='d0c1e000-0000-4000-8000-0000000000f1'));
select supabase_tests.check('follow balik → follow_user mengembalikan friend:true',
  (select v::jsonb->>'friend' from _fr where k='follow_back') = 'true',
  (select v from _fr where k='follow_back'));
select supabase_tests.check('follow balik → _are_friends (story) true',
  public._are_friends('d0c1e000-0000-4000-8000-0000000000f1', 'd0c1e000-0000-4000-8000-0000000000f2'));
select supabase_tests.check('follow balik → _privacy_are_friends true',
  public._privacy_are_friends('d0c1e000-0000-4000-8000-0000000000f1', 'd0c1e000-0000-4000-8000-0000000000f2'));
select supabase_tests.check('request pending B→A jadi accepted',
  (select status from public.friend_requests where from_id='d0c1e000-0000-4000-8000-0000000000f2' and to_id='d0c1e000-0000-4000-8000-0000000000f1') = 'accepted');

-- ── 2. Request ke orang yang sudah follow saya → langsung teman ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f4', true);
select public.follow_user('d0c1e000-0000-4000-8000-0000000000f3'); -- D follow C
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f3', true);
insert into _fr values ('req_to_follower', public.send_friend_request('d0c1e000-0000-4000-8000-0000000000f4')::text);
select supabase_tests.check('request ke follower → already_friends',
  (select v::jsonb->>'already_friends' from _fr where k='req_to_follower') = 'true',
  (select v from _fr where k='req_to_follower'));
select supabase_tests.check('C & D saling follow = teman',
  public._are_friends('d0c1e000-0000-4000-8000-0000000000f3', 'd0c1e000-0000-4000-8000-0000000000f4'));

-- ── 3. Tolak → follow buatan request dihapus ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f1', true);
select public.send_friend_request('d0c1e000-0000-4000-8000-0000000000f3'); -- A minta ke C
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f3', true);
select public.respond_friend_request(
  (select id from public.friend_requests where from_id='d0c1e000-0000-4000-8000-0000000000f1' and to_id='d0c1e000-0000-4000-8000-0000000000f3'),
  false);
select supabase_tests.check('tolak → follow A→C (buatan request) dihapus',
  not exists(select 1 from public.follows where follower_id='d0c1e000-0000-4000-8000-0000000000f1' and followee_id='d0c1e000-0000-4000-8000-0000000000f3'));

-- ── 4. Follow yang SUDAH ada sebelum request tidak ikut dihapus saat tolak ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f2', true);
select public.follow_user('d0c1e000-0000-4000-8000-0000000000f4');        -- B follow D dulu
select public.send_friend_request('d0c1e000-0000-4000-8000-0000000000f4'); -- lalu minta teman
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f4', true);
select public.respond_friend_request(
  (select id from public.friend_requests where from_id='d0c1e000-0000-4000-8000-0000000000f2' and to_id='d0c1e000-0000-4000-8000-0000000000f4'),
  false);
select supabase_tests.check('tolak → follow B→D lama tetap ada',
  exists(select 1 from public.follows where follower_id='d0c1e000-0000-4000-8000-0000000000f2' and followee_id='d0c1e000-0000-4000-8000-0000000000f4'));

-- ── 5. Batalkan request → follow buatan request hilang ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f1', true);
select public.send_friend_request('d0c1e000-0000-4000-8000-0000000000f4'); -- A minta ke D
select public.cancel_friend_request(
  (select id from public.friend_requests where from_id='d0c1e000-0000-4000-8000-0000000000f1' and to_id='d0c1e000-0000-4000-8000-0000000000f4'));
select supabase_tests.check('cancel → follow A→D (buatan request) hilang',
  not exists(select 1 from public.follows where follower_id='d0c1e000-0000-4000-8000-0000000000f1' and followee_id='d0c1e000-0000-4000-8000-0000000000f4'));

-- ── 6. Accepted tanpa saling follow (data basi) → BUKAN teman ──
insert into public.friend_requests (from_id, to_id, status, responded_at)
values ('d0c1e000-0000-4000-8000-0000000000f3', 'd0c1e000-0000-4000-8000-0000000000f2', 'accepted', now());
select supabase_tests.check('accepted basi tanpa saling follow → _are_friends false',
  not public._are_friends('d0c1e000-0000-4000-8000-0000000000f3', 'd0c1e000-0000-4000-8000-0000000000f2'));

-- ── 7. Unfollow = putus penuh ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000f1', true);
select public.unfollow_user('d0c1e000-0000-4000-8000-0000000000f2');
select supabase_tests.check('unfollow → A & B bukan teman lagi',
  not public._are_friends('d0c1e000-0000-4000-8000-0000000000f1', 'd0c1e000-0000-4000-8000-0000000000f2'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
