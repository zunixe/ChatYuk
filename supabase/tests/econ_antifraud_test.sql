-- Lapis 3: Anti-fraud Fase B (20261107000000/010000).
--   B1: send_coins — penerima terima NET (default cut 30% ke
--       platform_revenue coin_send_cut).
--   B2: request_withdraw — KYC_REQUIRED bila belum approved;
--       flag withdraw_require_kyc=false mem-bypass.
--   B3: cooldown ganti nomor DANA (request_withdraw & save_withdraw_account).
--   B4: admin_withdraw_process approve wajib p_tx_id; reject tidak.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();
-- Masa tahan (20261109020000) diuji di withdraw_hold_refund_test; di sini 0
-- supaya saldo earned seed (dibuat "sekarang") bisa langsung ditarik.
update public.app_settings set withdraw_hold_days = 0 where id = 'global';

select supabase_tests.mk_dummy('ed070000-0000-4000-8000-0000000000a1'::uuid, '[TEST] B-M1', 'online');
select supabase_tests.mk_dummy('ed070000-0000-4000-8000-0000000000f1'::uuid, '[TEST] B-F1', 'online');
update public.profiles set gender='female',
       created_at = now() - interval '30 days',
       is_registered = true
 where id in ('ed070000-0000-4000-8000-0000000000a1',
              'ed070000-0000-4000-8000-0000000000f1');
update public.profiles set is_registered = true
 where id = 'ed070000-0000-4000-8000-0000000000a1';

-- Pengirim berkantong topup; female punya earned untuk withdraw.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed070000-0000-4000-8000-0000000000a1','topup','topup',1000,'test-b'),
       ('ed070000-0000-4000-8000-0000000000f1','earned','test_seed',5000,'test-b'),
       ('ed070000-0000-4000-8000-0000000000f1','topup','topup',100,'test-b');

-- Chat 1:1 nyata untuk send_coins.
insert into public.private_chats (chat_id, participants)
values ('test-b-chat', array['ed070000-0000-4000-8000-0000000000a1'::uuid,
                            'ed070000-0000-4000-8000-0000000000f1'::uuid]);

create temp table _b (k text primary key, v text) on commit drop;
grant all on _b to service_role;

-- ════ B1a. send_coins 100 → penerima +70, platform +30 ════
select set_config('request.jwt.claim.sub',
                  'ed070000-0000-4000-8000-0000000000a1', true);
insert into _b values ('s1', public.send_coins(
  'test-b-chat', 'ed070000-0000-4000-8000-0000000000f1', 100)::text);
select supabase_tests.check('B: send_coins 100 → ok, received=70',
  (select (v::jsonb->>'ok')::boolean from _b where k='s1') = true
  and (select (v::jsonb->>'received')::int from _b where k='s1') = 70,
  (select v from _b where k='s1'));
select supabase_tests.check('B: pengirim −100 topup',
  exists (select 1 from public.coin_ledger
          where user_id='ed070000-0000-4000-8000-0000000000a1'
            and type='coin_sent' and amount=-100));
select supabase_tests.check('B: penerima +70 coin_received (NET)',
  exists (select 1 from public.coin_ledger
          where user_id='ed070000-0000-4000-8000-0000000000f1'
            and bucket='earned' and type='coin_received' and amount=70)
  and not exists (select 1 from public.coin_ledger
          where user_id='ed070000-0000-4000-8000-0000000000f1'
            and type='coin_received' and amount=100));
select supabase_tests.check('B: platform_revenue coin_send_cut 30',
  exists (select 1 from public.platform_revenue
          where source='coin_send_cut' and amount=30
            and from_user='ed070000-0000-4000-8000-0000000000a1'
            and to_user='ed070000-0000-4000-8000-0000000000f1'));

-- B1b. cut_pct=0 → transfer penuh (admin flag).
update public.app_settings set coin_send_cut_pct = 0 where id='global';
insert into _b values ('s2', public.send_coins(
  'test-b-chat', 'ed070000-0000-4000-8000-0000000000f1', 50)::text);
select supabase_tests.check('B: cut 0% → received=sent (50)',
  (select (v::jsonb->>'received')::int from _b where k='s2') = 50
  and exists (select 1 from public.coin_ledger
          where user_id='ed070000-0000-4000-8000-0000000000f1'
            and type='coin_received' and amount=50),
  (select v from _b where k='s2'));
update public.app_settings set coin_send_cut_pct = 30 where id='global';

-- ════ B2. Gerbang KYC ════
select set_config('request.jwt.claim.sub',
                  'ed070000-0000-4000-8000-0000000000f1', true);
insert into _b values ('w_nokyc',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('B: tanpa KYC → KYC_REQUIRED',
  (select v::jsonb->>'error' from _b where k='w_nokyc') = 'KYC_REQUIRED',
  (select v from _b where k='w_nokyc'));
select supabase_tests.check('B: KYC_REQUIRED → earned tak terdebit',
  not exists (select 1 from public.coin_ledger
          where user_id='ed070000-0000-4000-8000-0000000000f1'
            and type='withdraw'));

-- KYC pending (bukan approved) tetap ditolak.
insert into public.kyc_requests (user_id, status, full_name, id_number,
                                 id_photo, selfie_photo)
values ('ed070000-0000-4000-8000-0000000000f1', 'pending',
        '[TEST] F1', '3201', 'x', 'x');
insert into _b values ('w_pend',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('B: KYC pending → tetap KYC_REQUIRED',
  (select v::jsonb->>'error' from _b where k='w_pend') = 'KYC_REQUIRED',
  (select v from _b where k='w_pend'));

-- Approved → lolos gate.
update public.kyc_requests set status='approved'
 where user_id='ed070000-0000-4000-8000-0000000000f1';
insert into _b values ('w_ok',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('B: KYC approved → withdraw ok',
  (select (v::jsonb->>'ok')::boolean from _b where k='w_ok') = true,
  (select v from _b where k='w_ok'));

-- Flag OFF → bypass (admin kill-switch).
update public.app_settings set withdraw_require_kyc = false where id='global';
insert into _b values ('w_flag',
  public.request_withdraw(100, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('B: flag off → bukan KYC_REQUIRED',
  (select coalesce(v::jsonb->>'error','ok') from _b where k='w_flag')
    <> 'KYC_REQUIRED',
  (select v from _b where k='w_flag'));
update public.app_settings set withdraw_require_kyc = true where id='global';

-- ════ B3. Cooldown ganti nomor DANA ════
-- f1 sudah punya akun 081234567890 dari withdraw tadi. Mundurkan
-- created_at request agar gate TOO_SOON tidak menang lebih dulu.
update public.withdrawal_requests set created_at = now() - interval '2 hours'
 where user_id = 'ed070000-0000-4000-8000-0000000000f1';
insert into _b values ('w_diff',
  public.request_withdraw(2000, '089999888777', '[TEST] Lain')::text);
select supabase_tests.check('B: ganti nomor <168 jam → DANA_CHANGE_COOLDOWN',
  (select v::jsonb->>'error' from _b where k='w_diff')
    = 'DANA_CHANGE_COOLDOWN',
  (select v from _b where k='w_diff'));

-- Nomor sama tapi nama berubah → bukan cooldown (TOO_SOON/DAILY_LIMIT
-- bisa menyusul — yang penting BUKAN DANA_CHANGE_COOLDOWN).
insert into _b values ('w_same',
  public.request_withdraw(2000, '081234567890', '[TEST] Nama Baru')::text);
select supabase_tests.check('B: nomor sama ganti nama → bukan cooldown DANA',
  (select coalesce(v::jsonb->>'error','ok') from _b where k='w_same')
    <> 'DANA_CHANGE_COOLDOWN',
  (select v from _b where k='w_same'));

-- save_withdraw_account jalur terpisah: nomor beda → cooldown juga.
insert into _b values ('sa_diff',
  public.save_withdraw_account('08111222333', '[TEST] Lain')::text);
select supabase_tests.check('B: save_account nomor beda → DANA_CHANGE_COOLDOWN',
  (select v::jsonb->>'error' from _b where k='sa_diff')
    = 'DANA_CHANGE_COOLDOWN',
  (select v from _b where k='sa_diff'));
insert into _b values ('sa_same',
  public.save_withdraw_account('081234567890', '[TEST] Nama Edit')::text);
select supabase_tests.check('B: save_account nomor sama → ok',
  (select (v::jsonb->>'ok')::boolean from _b where k='sa_same') = true,
  (select v from _b where k='sa_same'));

-- Nomor lama lewat cooldown → boleh ganti.
update public.withdraw_accounts
   set updated_at = now() - interval '200 hours'
 where user_id = 'ed070000-0000-4000-8000-0000000000f1';
insert into _b values ('sa_free',
  public.save_withdraw_account('08111222333', '[TEST] Lain')::text);
select supabase_tests.check('B: lewat cooldown → ganti nomor ok',
  (select (v::jsonb->>'ok')::boolean from _b where k='sa_free') = true
  and (select v::jsonb->>'dana_number' from _b where k='sa_free')
    = '08111222333',
  (select v from _b where k='sa_free'));

-- ════ B4. tx_id wajib untuk approve ════
-- Request baru (pending) milik f1 dari langkah 'w_ok' masih ada.
select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
insert into _b values ('ap_notx',
  public.admin_withdraw_process(
    (select id from public.withdrawal_requests
      where user_id='ed070000-0000-4000-8000-0000000000f1'
        and status='pending' order by created_at desc limit 1),
    true, 'catatan')::text);
select supabase_tests.check('B: approve tanpa tx_id → TX_ID_REQUIRED',
  (select v::jsonb->>'error' from _b where k='ap_notx') = 'TX_ID_REQUIRED',
  (select v from _b where k='ap_notx'));
select supabase_tests.check('B: tanpa tx_id → status tetap pending',
  exists (select 1 from public.withdrawal_requests
          where user_id='ed070000-0000-4000-8000-0000000000f1'
            and status='pending'));

insert into _b values ('ap_ok',
  public.admin_withdraw_process(
    (select id from public.withdrawal_requests
      where user_id='ed070000-0000-4000-8000-0000000000f1'
        and status='pending' order by created_at desc limit 1),
    true, 'catatan', 'DANA-TRX-001')::text);
select supabase_tests.check('B: approve +tx_id → paid & tx_id tersimpan',
  (select (v::jsonb->>'ok')::boolean from _b where k='ap_ok') = true
  and exists (select 1 from public.withdrawal_requests
          where user_id='ed070000-0000-4000-8000-0000000000f1'
            and status='paid' and tx_id='DANA-TRX-001'),
  (select v from _b where k='ap_ok'));

-- Reject tetap tanpa tx_id (bukan kewajiban).
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed070000-0000-4000-8000-0000000000f1','earned','test_seed',3000,'test-b2');
update public.withdraw_accounts
   set updated_at = now() - interval '200 hours'
 where user_id = 'ed070000-0000-4000-8000-0000000000f1';
select set_config('request.jwt.claim.sub',
                  'ed070000-0000-4000-8000-0000000000f1', true);
select set_config('request.jwt.claim.email', '', true);
update public.withdrawal_requests set created_at = now() - interval '2 hours'
 where user_id = 'ed070000-0000-4000-8000-0000000000f1';
insert into _b values ('w2',
  public.request_withdraw(2000, '08111222333', '[TEST] Lain')::text);
select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
insert into _b values ('rj_ok',
  public.admin_withdraw_process(
    (select id from public.withdrawal_requests
      where user_id='ed070000-0000-4000-8000-0000000000f1'
        and status='pending' order by created_at desc limit 1),
    false, 'batal')::text);
select supabase_tests.check('B: reject tanpa tx_id → refunded',
  (select (v::jsonb->>'ok')::boolean from _b where k='rj_ok') = true
  and (select (v::jsonb->>'refunded')::int from _b where k='rj_ok') = 2000,
  (select v from _b where k='rj_ok'));
select set_config('request.jwt.claim.email', '', true);

select supabase_tests.report() as result;
rollback;
