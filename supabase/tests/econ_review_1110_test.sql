-- Lapis 3: review ulang ekonomi 2026-11-10 (20261110000000/010000/020000).
--   P1: withdraw_accounts & subscriptions read-only untuk klien.
--   P1: profiles.subscription_price & is_registered tak bisa dipalsukan.
--   P1: nomor DANA unik antar akun; subscribe_creator PRICE_CHANGED.
--   P1: akun berbagi device → UNDER_REVIEW; approve admin cek fraud_holds.
--   P2: call berakhir → server menagih payer (tanpa tick dari klien).
--   P3: refund berantai A→B→C menahan C.
--   P4: level dari order paid (refund chat tak menaikkan); misi dibatasi.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed0c0000-0000-4000-8000-0000000000a1'::uuid, '[TEST] R-A', 'online');
select supabase_tests.mk_dummy('ed0c0000-0000-4000-8000-0000000000b1'::uuid, '[TEST] R-B', 'online');
select supabase_tests.mk_dummy('ed0c0000-0000-4000-8000-0000000000c1'::uuid, '[TEST] R-C', 'online');
update public.profiles set gender = 'male', is_registered = true,
       created_at = now() - interval '30 days'
 where id in ('ed0c0000-0000-4000-8000-0000000000a1',
              'ed0c0000-0000-4000-8000-0000000000b1');
update public.profiles set gender = 'female', is_registered = true,
       created_at = now() - interval '30 days', subscription_price = 50
 where id = 'ed0c0000-0000-4000-8000-0000000000c1';
update public.app_settings
   set withdraw_hold_days = 0, withdraw_require_kyc = false,
       feature_flags = feature_flags || '{"call_billing":{"published":true}}'::jsonb
 where id = 'global';

create temp table _r (k text primary key, ok boolean, msg text) on commit drop;
grant all on _r to service_role, authenticated;

-- ════ P1. Tulis langsung oleh klien ════
do $$
declare v_msg text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000c1', true);
  begin
    insert into public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
    values ('ed0c0000-0000-4000-8000-0000000000c1', '081111111111', 'X', '2020-01-01');
    v_msg := 'no exception';
  exception when others then v_msg := sqlerrm; end;
  insert into _r values ('wa', v_msg <> 'no exception', v_msg);
  begin
    insert into public.subscriptions (subscriber_id, creator_id, price, starts_at, expires_at)
    values ('ed0c0000-0000-4000-8000-0000000000c1', 'ed0c0000-0000-4000-8000-0000000000a1',
            0, now(), '2099-01-01');
    v_msg := 'no exception';
  exception when others then v_msg := sqlerrm; end;
  insert into _r values ('sub', v_msg <> 'no exception', v_msg);
  -- Harga langganan & status terdaftar via PATCH langsung → diabaikan.
  update public.profiles set subscription_price = 99999
   where id = 'ed0c0000-0000-4000-8000-0000000000c1';
  reset role;
end $$;
select supabase_tests.check('P1: insert withdraw_accounts langsung → ditolak',
  (select ok from _r where k='wa'), (select msg from _r where k='wa'));
select supabase_tests.check('P1: insert subscriptions langsung → ditolak',
  (select ok from _r where k='sub'), (select msg from _r where k='sub'));
select supabase_tests.check('P1: PATCH subscription_price diabaikan',
  (select subscription_price from public.profiles
    where id = 'ed0c0000-0000-4000-8000-0000000000c1') = 50);

-- is_registered: akun dummy tanpa auth terverifikasi tak bisa naik ke true.
update public.profiles set is_registered = false
 where id = 'ed0c0000-0000-4000-8000-0000000000b1';
-- mk_dummy membuat auth user terverifikasi → kosongkan supaya "belum verifikasi".
update auth.users set email_confirmed_at = null, phone_confirmed_at = null
 where id = 'ed0c0000-0000-4000-8000-0000000000b1';
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000b1', true);
  update public.profiles set is_registered = true
   where id = 'ed0c0000-0000-4000-8000-0000000000b1';
  reset role;
end $$;
select supabase_tests.check('P1: is_registered=true tanpa verifikasi → tetap false',
  (select is_registered from public.profiles
    where id = 'ed0c0000-0000-4000-8000-0000000000b1') = false);
update public.profiles set is_registered = true
 where id = 'ed0c0000-0000-4000-8000-0000000000b1';

-- ════ P1. Nomor DANA unik & harga langganan terkunci ════
select set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000a1', true);
select supabase_tests.check('P1: save_withdraw_account akun A ok',
  (public.save_withdraw_account('081222333444', '[TEST] A')->>'ok')::boolean);
select set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000c1', true);
select supabase_tests.check('P1: nomor sama di akun C → DANA_IN_USE',
  public.save_withdraw_account('081222333444', '[TEST] C')->>'error' = 'DANA_IN_USE');

insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed0c0000-0000-4000-8000-0000000000a1','topup','topup',2000,'r-a');
select set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000a1', true);
do $$
declare v_msg text := 'no exception';
begin
  begin
    perform public.subscribe_creator('ed0c0000-0000-4000-8000-0000000000c1', 1, 40);
  exception when others then v_msg := sqlerrm; end;
  insert into _r values ('pc', v_msg like '%PRICE_CHANGED%', v_msg);
end $$;
select supabase_tests.check('P1: subscribe dgn harga beda → PRICE_CHANGED',
  (select ok from _r where k='pc'), (select msg from _r where k='pc'));

-- ════ P2. Call berakhir tanpa tick klien → server menagih ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ed0c0000-0000-4000-8000-0000000000d1'::uuid,
        'ed0c0000-0000-4000-8000-0000000000a1',
        'ed0c0000-0000-4000-8000-0000000000c1',
        'direct', 'video', 'answered', now() - interval '125 seconds');
update public.calls set status = 'ended', ended_at = now()
 where id = 'ed0c0000-0000-4000-8000-0000000000d1';
select supabase_tests.check('P2: hangup tanpa tick → server menagih 3 menit',
  (select count(*) from public.yukcoin_consumptions
    where ref_id = 'ed0c0000-0000-4000-8000-0000000000d1') = 3);
select supabase_tests.check('P2: _call_bill_as tidak executable authenticated',
  has_function_privilege('authenticated', 'public._call_bill_as(uuid,uuid)', 'execute') = false);

-- ════ P3. Refund berantai A → B → C ════
insert into public.topup_orders (id, user_id, package_id, coins, price_idr, status,
                                 provider, purchase_token, platform, paid_at)
values ('play_test_chain', 'ed0c0000-0000-4000-8000-0000000000a1',
        (select id from public.topup_packages order by price_idr limit 1),
        2000, 25000, 'paid', 'play_billing', 'tok-test-chain', 'play',
        now() - interval '2 days');
insert into public.platform_revenue (source, amount, from_user, to_user, ref_id)
values ('coin_send_cut', 30, 'ed0c0000-0000-4000-8000-0000000000a1',
        'ed0c0000-0000-4000-8000-0000000000b1', 'x'),
       ('gift_cut', 20, 'ed0c0000-0000-4000-8000-0000000000b1',
        'ed0c0000-0000-4000-8000-0000000000c1', 'y');
select public.reverse_play_topup('tok-test-chain', 'test');
select supabase_tests.check('P3: penerima tidak langsung (C) ikut ditahan',
  exists (select 1 from public.fraud_holds
          where user_id = 'ed0c0000-0000-4000-8000-0000000000c1'
            and ref_id = 'play_test_chain' and resolved_at is null));

-- Approve admin → ditolak selama C ditahan.
insert into public.withdrawal_requests (user_id, coin_amount, payout_idr, gross_idr,
                                        fee_idr, rate, status, pay_method, pay_account,
                                        pay_holder)
values ('ed0c0000-0000-4000-8000-0000000000c1', 2000, 13000, 14000, 1000, 7,
        'pending', 'ewallet', '081999', '[TEST] C');
select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
select supabase_tests.check('P1: approve admin saat ditahan → UNDER_REVIEW',
  public.admin_withdraw_process(
    (select id from public.withdrawal_requests
      where user_id = 'ed0c0000-0000-4000-8000-0000000000c1' and status = 'pending'),
    true, null, 'TX-1')->>'error' = 'UNDER_REVIEW');
select set_config('request.jwt.claim.email', '', true);

-- ════ P4. Level dari order paid ════
select set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000b1', true);
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed0c0000-0000-4000-8000-0000000000b1','topup','spend_refund',5000,'image');
select supabase_tests.check('P4: kredit topup non-order (spend_refund) tak menaikkan level',
  (public.get_my_level()->>'level')::int = 0);
select supabase_tests.check('P4: order refunded tak dihitung (A level 0)',
  public.level_paid_coins('ed0c0000-0000-4000-8000-0000000000a1') = 0);

-- Misi dari klien: increment besar dipotong.
do $$
declare v jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'ed0c0000-0000-4000-8000-0000000000b1', true);
  v := public.update_mission_progress('ed0c0000-0000-4000-8000-0000000000b1',
                                      'call_minutes', 120);
  reset role;
  insert into _r values ('mi', (v->>'progress')::int <= 1, v::text);
end $$;
select supabase_tests.check('P4: update_mission_progress(120) dari klien → maks 1',
  (select ok from _r where k='mi'), (select msg from _r where k='mi'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
