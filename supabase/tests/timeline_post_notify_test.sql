-- Lapis 3: notif post timeline sesuai visibilitas + get_post — 20260929213300.
-- Jalankan: scripts/run_sql_tests.sh timeline_post_notify_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
-- Aturan: public → SEMUA (registered, non-dummy, non-exclude);
--   followers → follower saja; subscribers → subscriber aktif saja.
--   get_post → 1 post bila boleh lihat (cermin list_posts), else NULL.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000011'::uuid, 'TEST PostOwn', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000012'::uuid, 'TEST Follower');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000013'::uuid, 'TEST Stranger');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000014'::uuid, 'TEST SubActive');

-- Follower searah (dia follow owner).
insert into public.follows (follower_id, followee_id) values
 ('d0c1e000-0000-4000-8000-000000000012', 'd0c1e000-0000-4000-8000-000000000011');
-- Subscriber aktif.
insert into public.subscriptions (subscriber_id, creator_id, price, expires_at) values
 ('d0c1e000-0000-4000-8000-000000000014', 'd0c1e000-0000-4000-8000-000000000011', 1, now() + interval '30 days');

-- Tiga post owner: public / followers / subscribers.
insert into public.posts (id, author_id, author_name, text, visibility) values
 ('e0c1e000-0000-4000-8000-000000000001', 'd0c1e000-0000-4000-8000-000000000011', 'TEST PostOwn', 'public hello', 'public'),
 ('e0c1e000-0000-4000-8000-000000000002', 'd0c1e000-0000-4000-8000-000000000011', 'TEST PostOwn', 'followers hello', 'followers'),
 ('e0c1e000-0000-4000-8000-000000000003', 'd0c1e000-0000-4000-8000-000000000011', 'TEST PostOwn', 'subs hello', 'subscribers');

-- ── get_post sebagai stranger ──
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000013","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('get_post: public terlihat stranger',
  (public.get_post('e0c1e000-0000-4000-8000-000000000001'::uuid)->>'text') = 'public hello');
select supabase_tests.check('get_post: followers tersembunyi dari stranger',
  public.get_post('e0c1e000-0000-4000-8000-000000000002'::uuid) is null);
select supabase_tests.check('get_post: subscribers tersembunyi dari stranger',
  public.get_post('e0c1e000-0000-4000-8000-000000000003'::uuid) is null);
select supabase_tests.check('get_post: id tak ada → null',
  public.get_post('e0c1e000-0000-4000-8000-000000000099'::uuid) is null);

-- ── get_post sebagai follower ──
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000012","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('get_post: followers terlihat follower',
  (public.get_post('e0c1e000-0000-4000-8000-000000000002'::uuid)->>'text') = 'followers hello');
select supabase_tests.check('get_post: subscribers tersembunyi dari follower',
  public.get_post('e0c1e000-0000-4000-8000-000000000003'::uuid) is null);

-- ── get_post sebagai subscriber ──
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000014","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('get_post: subscribers terlihat subscriber',
  (public.get_post('e0c1e000-0000-4000-8000-000000000003'::uuid)->>'text') = 'subs hello');

-- ── get_post sebagai author ──
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000011","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('get_post: author lihat semua miliknya',
  (public.get_post('e0c1e000-0000-4000-8000-000000000003'::uuid)->>'text') = 'subs hello');

-- ── get_post sebagai anon non-dummy → ANON_DISABLED ──
insert into auth.users (id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at, created_at, updated_at)
values ('d0c1e000-0000-4000-8000-000000000015', '00000000-0000-4000-8000-000000000000',
  'authenticated', 'authenticated', 'anon15@test.local', '', now(), now(), now())
on conflict (id) do nothing;
insert into public.profiles (id, nickname, is_registered, status, last_seen)
values ('d0c1e000-0000-4000-8000-000000000015', 'TEST Anon', false, 'online', now())
on conflict (id) do update set is_registered = false;
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000015","email":"t@t.local","role":"authenticated"}', false);
do $$
begin
  begin
    perform public.get_post('e0c1e000-0000-4000-8000-000000000001'::uuid);
    perform set_config('supabase_tests.anon_guard', 'no_raise', true);
  exception when others then
    perform set_config('supabase_tests.anon_guard', 'raised', true);
  end;
end $$;
select supabase_tests.check('get_post: anon ditolak (ANON_DISABLED)',
  current_setting('supabase_tests.anon_guard', true) = 'raised');

-- ── Definisi trigger sesuai visibilitas ──
select supabase_tests.check('notify_post_followers: cabang public→semua',
  (select pg_get_functiondef(p.oid) like '%public (dan fallback)%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'notify_post_followers'));
select supabase_tests.check('fanout: hanya public',
  (select pg_get_functiondef(p.oid) like '%<> ''public''%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'notify_timeline_post_fanout'));
select supabase_tests.check('notify: public→semua lewati author dummy',
  (select pg_get_functiondef(p.oid) like '%v_author_dummy%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'notify_post_followers'));
select supabase_tests.check('get_post: gate anon',
  (select pg_get_functiondef(p.oid) like '%ANON_DISABLED%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_post'));

select supabase_tests.report() as result;
rollback;
