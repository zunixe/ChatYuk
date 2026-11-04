-- Lapis 3: hadiah misi perempuan bisa ditarik (20261110040000).
--   F1: female device unik → earned; device tercatat milik dia.
--   F2: akun lain (anonim) di device yang sama → bonus shared_device.
--   F3: female beda device, IP sama < 24 jam → bonus shared_ip.
--   F4: female tanpa device → bonus no_device.
--   F5: male → selalu bonus.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed0d0000-0000-4000-8000-0000000000f1'::uuid, '[TEST] MP-F1', 'online');
select supabase_tests.mk_dummy('ed0d0000-0000-4000-8000-0000000000f2'::uuid, '[TEST] MP-F2', 'online');
select supabase_tests.mk_dummy('ed0d0000-0000-4000-8000-0000000000f3'::uuid, '[TEST] MP-F3', 'online');
select supabase_tests.mk_dummy('ed0d0000-0000-4000-8000-0000000000f4'::uuid, '[TEST] MP-F4', 'online');
select supabase_tests.mk_dummy('ed0d0000-0000-4000-8000-0000000000a1'::uuid, '[TEST] MP-M1', 'online');
update public.profiles set gender = 'female'
 where id in ('ed0d0000-0000-4000-8000-0000000000f1', 'ed0d0000-0000-4000-8000-0000000000f2',
              'ed0d0000-0000-4000-8000-0000000000f3', 'ed0d0000-0000-4000-8000-0000000000f4');
update public.profiles set gender = 'male'
 where id = 'ed0d0000-0000-4000-8000-0000000000a1';

-- F1 & F2 berbagi device; F3 device sendiri; M1 device sendiri; F4 tanpa device.
insert into public.user_devices (user_id, install_id) values
  ('ed0d0000-0000-4000-8000-0000000000f1', 'drm-test-mp-shared'),
  ('ed0d0000-0000-4000-8000-0000000000f2', 'drm-test-mp-shared'),
  ('ed0d0000-0000-4000-8000-0000000000f3', 'drm-test-mp-f3'),
  ('ed0d0000-0000-4000-8000-0000000000a1', 'drm-test-mp-m1');

insert into public.user_missions (user_id, mission_id, progress, is_completed, period_date)
select u.id, m.id, 3, true, null
  from public.missions m,
       (values ('ed0d0000-0000-4000-8000-0000000000f1'::uuid),
               ('ed0d0000-0000-4000-8000-0000000000f2'::uuid),
               ('ed0d0000-0000-4000-8000-0000000000f3'::uuid),
               ('ed0d0000-0000-4000-8000-0000000000f4'::uuid),
               ('ed0d0000-0000-4000-8000-0000000000a1'::uuid)) u(id)
 where m.mission_key = 'like_posts';

create temp table _mp (k text primary key, v jsonb) on commit drop;
grant all on _mp to service_role;

-- IP palsu lewat header request (seperti PostgREST).
select set_config('request.headers', '{"x-forwarded-for":"203.0.113.7, 10.0.0.1"}', true);
select supabase_tests.check('IP diambil dari header (pertama di x-forwarded-for)',
  public._request_ip() = '203.0.113.7', public._request_ip());

select set_config('request.jwt.claim.sub', 'ed0d0000-0000-4000-8000-0000000000f1', true);
insert into _mp values ('f1', public.claim_mission_reward('ed0d0000-0000-4000-8000-0000000000f1', 'like_posts'));
select supabase_tests.check('F1: female device unik → earned',
  (select v->>'bucket' from _mp where k='f1') = 'earned', (select v::text from _mp where k='f1'));
select supabase_tests.check('F1: device tercatat milik F1',
  (select user_id from public.mission_payout_devices where install_id = 'drm-test-mp-shared')
    = 'ed0d0000-0000-4000-8000-0000000000f1');

-- IP berbeda supaya yang diuji murni device.
select set_config('request.headers', '{"x-forwarded-for":"198.51.100.20"}', true);
select set_config('request.jwt.claim.sub', 'ed0d0000-0000-4000-8000-0000000000f2', true);
insert into _mp values ('f2', public.claim_mission_reward('ed0d0000-0000-4000-8000-0000000000f2', 'like_posts'));
select supabase_tests.check('F2: akun lain di device yang sama → bonus shared_device',
  (select v->>'bucket' from _mp where k='f2') = 'bonus'
  and (select v->>'reason' from _mp where k='f2') = 'shared_device',
  (select v::text from _mp where k='f2'));

-- IP sama dengan klaim F1 (< 24 jam), device berbeda.
select set_config('request.headers', '{"x-forwarded-for":"203.0.113.7"}', true);
select set_config('request.jwt.claim.sub', 'ed0d0000-0000-4000-8000-0000000000f3', true);
insert into _mp values ('f3', public.claim_mission_reward('ed0d0000-0000-4000-8000-0000000000f3', 'like_posts'));
select supabase_tests.check('F3: IP sama < 24 jam → bonus shared_ip',
  (select v->>'bucket' from _mp where k='f3') = 'bonus'
  and (select v->>'reason' from _mp where k='f3') = 'shared_ip',
  (select v::text from _mp where k='f3'));

select set_config('request.headers', '{"x-forwarded-for":"192.0.2.44"}', true);
select set_config('request.jwt.claim.sub', 'ed0d0000-0000-4000-8000-0000000000f4', true);
insert into _mp values ('f4', public.claim_mission_reward('ed0d0000-0000-4000-8000-0000000000f4', 'like_posts'));
select supabase_tests.check('F4: female tanpa device → bonus no_device',
  (select v->>'bucket' from _mp where k='f4') = 'bonus'
  and (select v->>'reason' from _mp where k='f4') = 'no_device',
  (select v::text from _mp where k='f4'));

select set_config('request.jwt.claim.sub', 'ed0d0000-0000-4000-8000-0000000000a1', true);
insert into _mp values ('m1', public.claim_mission_reward('ed0d0000-0000-4000-8000-0000000000a1', 'like_posts'));
select supabase_tests.check('F5: male → bonus',
  (select v->>'bucket' from _mp where k='m1') = 'bonus', (select v::text from _mp where k='m1'));

select supabase_tests.check('_mission_payout_eligible tidak executable authenticated',
  has_function_privilege('authenticated', 'public._mission_payout_eligible(uuid,text)', 'execute') = false);
select supabase_tests.check('mission_payout_devices tidak bisa dibaca authenticated',
  has_table_privilege('authenticated', 'public.mission_payout_devices', 'select') = false);

select set_config('request.headers', '', true);
select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
