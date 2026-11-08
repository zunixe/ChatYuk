-- Lapis 3: PEREMPUAN GRATIS SEMUA (20261110090000).
--   F1: deduct_chat_point('image') female → tidak ada spend_chat.
--   F2: create_private_room / extend_private_room female → tidak ada spend_room,
--       room tetap dibuat & diperpanjang.
--   F3: subscribe_creator female → gratis, kreator TIDAK dapat earned,
--       langganan tetap tercatat.
--   M1: male tetap ditagih foto (perilaku lama).
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed11e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] FF-M1', 'online');
select supabase_tests.mk_dummy('ed11e000-0000-4000-8000-0000000000f1'::uuid, '[TEST] FF-F1', 'online');
select supabase_tests.mk_dummy('ed11e000-0000-4000-8000-0000000000c1'::uuid, '[TEST] FF-C1', 'online');
update public.profiles set gender = 'male', is_registered = true,
       created_at = now() - interval '30 days'
 where id in ('ed11e000-0000-4000-8000-0000000000a1', 'ed11e000-0000-4000-8000-0000000000c1');
update public.profiles set gender = 'female', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'ed11e000-0000-4000-8000-0000000000f1';
update public.profiles set subscription_price = 50
 where id = 'ed11e000-0000-4000-8000-0000000000c1';
update public.app_settings
   set points_enabled = true, cost_chat_image = 5, room_create_paid = 50,
       room_extend_paid = 50
 where id = 'global';
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
  ('ed11e000-0000-4000-8000-0000000000a1', 'topup', 'topup', 500, '[TEST]ff'),
  ('ed11e000-0000-4000-8000-0000000000f1', 'earned', 'call_video_income', 500, '[TEST]ff');

create temp table _ff (k text primary key, v text) on commit drop;
grant all on _ff to service_role;

-- ════ F1. Foto female gratis ════
select set_config('request.jwt.claim.sub', 'ed11e000-0000-4000-8000-0000000000f1', true);
select public.deduct_chat_point('image');
select supabase_tests.check('F1: female kirim foto → tidak ada spend_chat',
  not exists (select 1 from public.coin_ledger
              where user_id='ed11e000-0000-4000-8000-0000000000f1' and type='spend_chat'));

-- ════ F2. Grup privat female gratis ════
insert into _ff values ('room',
  public.create_private_room('[TEST] FF Room', '🔒', 'ID', null, 'private')::text);
select supabase_tests.check('F2: female buat grup → room dibuat',
  exists (select 1 from public.rooms
          where id = (select v::jsonb->>'id' from _ff where k='room')));
select public.extend_private_room((select v::jsonb->>'id' from _ff where k='room'));
select supabase_tests.check('F2: female buat & perpanjang grup → tidak ada spend_room',
  not exists (select 1 from public.coin_ledger
              where user_id='ed11e000-0000-4000-8000-0000000000f1' and type='spend_room'));

-- ════ F3. Langganan female gratis, kreator tidak dapat ════
insert into _ff values ('sub',
  public.subscribe_creator('ed11e000-0000-4000-8000-0000000000c1', 1, 50)::text);
select supabase_tests.check('F3: female langganan → charged 0',
  (select (v::jsonb->>'charged')::int from _ff where k='sub') = 0,
  (select v from _ff where k='sub'));
select supabase_tests.check('F3: langganan tercatat',
  exists (select 1 from public.subscriptions
          where subscriber_id='ed11e000-0000-4000-8000-0000000000f1'
            and creator_id='ed11e000-0000-4000-8000-0000000000c1'
            and expires_at > now()));
select supabase_tests.check('F3: kreator tidak dapat subscribe_income',
  not exists (select 1 from public.coin_ledger
              where user_id='ed11e000-0000-4000-8000-0000000000c1'
                and type='subscribe_income'));
select supabase_tests.check('F3: tidak ada spend subscribe female',
  not exists (select 1 from public.coin_ledger
              where user_id='ed11e000-0000-4000-8000-0000000000f1' and type='subscribe'));

-- ════ M1. Male tetap ditagih foto ════
select set_config('request.jwt.claim.sub', 'ed11e000-0000-4000-8000-0000000000a1', true);
select public.deduct_chat_point('image');
select supabase_tests.check('M1: male kirim foto → spend_chat tercatat',
  exists (select 1 from public.coin_ledger
          where user_id='ed11e000-0000-4000-8000-0000000000a1' and type='spend_chat'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
