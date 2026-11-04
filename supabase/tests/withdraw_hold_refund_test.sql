-- Lapis 3: masa tahan withdraw + refund Play (20261109020000) dan billing
-- call (20261109030000).
--   H1: penghasilan < hold_days → HELD_BALANCE; yang lama → bisa ditarik.
--   H2: batas nominal harian → DAILY_AMOUNT_LIMIT.
--   H3: KYC dicek SEBELUM nomor DANA disimpan (N8).
--   H4: reward misi default bonus (female earned: female_mission_payout_test).
--   R1: reverse_play_topup — tarik koin pembeli, tahan pembeli+penerima,
--       withdraw penerima → UNDER_REVIEW; idempoten.
--   B1: private call tetap ditagih walau flag random_call mati.
--   B2: random tanpa media_connected_at → 0 tagihan.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed0b0000-0000-4000-8000-0000000000f1'::uuid, '[TEST] H-F1', 'online');
select supabase_tests.mk_dummy('ed0b0000-0000-4000-8000-0000000000a1'::uuid, '[TEST] H-M1', 'online');
update public.profiles set gender = 'female', created_at = now() - interval '30 days',
       is_registered = true
 where id = 'ed0b0000-0000-4000-8000-0000000000f1';
update public.profiles set gender = 'male', created_at = now() - interval '30 days',
       is_registered = true
 where id = 'ed0b0000-0000-4000-8000-0000000000a1';

update public.app_settings
   set withdraw_hold_days = 7, withdraw_max_coins_per_day = 5000,
       withdraw_min_coins = 2000, withdraw_require_kyc = true,
       feature_flags = feature_flags
         || '{"call_billing":{"published":true}}'::jsonb
         || '{"random_call":{"published":false}}'::jsonb
 where id = 'global';

create temp table _h (k text primary key, v text) on commit drop;
grant all on _h to service_role;

-- Penghasilan female: 3000 lama (10 hari lalu) + 4000 baru (kemarin).
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id, created_at)
values ('ed0b0000-0000-4000-8000-0000000000f1','earned','call_video_income',3000,'h-old', now() - interval '10 days'),
       ('ed0b0000-0000-4000-8000-0000000000f1','earned','call_video_income',4000,'h-new', now() - interval '1 day');

-- ════ H3. KYC belum approved → KYC_REQUIRED & nomor DANA TIDAK tersimpan ════
select set_config('request.jwt.claim.sub', 'ed0b0000-0000-4000-8000-0000000000f1', true);
insert into _h values ('k1', public.request_withdraw(2000, '081234567890', 'Siti Test')::text);
select supabase_tests.check('H3: tanpa KYC → KYC_REQUIRED',
  (select v::jsonb->>'error' from _h where k='k1') = 'KYC_REQUIRED',
  (select v from _h where k='k1'));
select supabase_tests.check('H3: nomor DANA tidak tersimpan saat KYC ditolak',
  not exists (select 1 from public.withdraw_accounts
              where user_id = 'ed0b0000-0000-4000-8000-0000000000f1'));

insert into public.kyc_requests (user_id, status, full_name, id_type, id_number,
                                 id_photo, selfie_photo, birth_date)
values ('ed0b0000-0000-4000-8000-0000000000f1', 'approved', '[TEST] H', 'ktp',
        '3273054508980009', repeat('A',120), repeat('B',120), '1998-08-05');

-- ════ H1. Masa tahan ════
insert into _h values ('h1', public.request_withdraw(3500, '081234567890', 'Siti Test')::text);
select supabase_tests.check('H1: minta 3500 (tersedia 3000) → HELD_BALANCE',
  (select v::jsonb->>'error' from _h where k='h1') = 'HELD_BALANCE'
  and (select (v::jsonb->>'available')::int from _h where k='h1') = 3000,
  (select v from _h where k='h1'));
insert into _h values ('h1b', public.request_withdraw(3000, '081234567890', 'Siti Test')::text);
select supabase_tests.check('H1: minta 3000 (sudah lewat masa tahan) → ok',
  (select (v::jsonb->>'ok')::boolean from _h where k='h1b') = true,
  (select v from _h where k='h1b'));
select supabase_tests.check('H1: get_earnings_summary withdrawable=0, held=4000',
  (public.get_earnings_summary('ed0b0000-0000-4000-8000-0000000000f1')->>'withdrawable')::int = 0
  and (public.get_earnings_summary('ed0b0000-0000-4000-8000-0000000000f1')->>'held')::int = 4000,
  public.get_earnings_summary('ed0b0000-0000-4000-8000-0000000000f1')::text);

-- ════ H2. Batas nominal harian (5000; sudah 3000 hari ini) ════
-- Masa tahan dimatikan dulu (ledger append-only → tak bisa mundurkan tgl).
update public.app_settings set withdraw_hold_days = 0 where id = 'global';
-- DAILY_AMOUNT_LIMIT dicek sebelum TOO_SOON → request tadi tak perlu dimundurkan.
insert into _h values ('h2', public.request_withdraw(2500)::text);
select supabase_tests.check('H2: 3000 + 2500 > 5000 → DAILY_AMOUNT_LIMIT remaining 2000',
  (select v::jsonb->>'error' from _h where k='h2') = 'DAILY_AMOUNT_LIMIT'
  and (select (v::jsonb->>'remaining')::int from _h where k='h2') = 2000,
  (select v from _h where k='h2'));

-- ════ H4. Reward misi female → bonus ════
select supabase_tests.check('H4: claim_mission_reward default bucket bonus (female earned hanya via _mission_payout_eligible)',
  position('v_reward_bucket := ''bonus''' in
    pg_get_functiondef('public.claim_mission_reward'::regproc)) > 0);

-- ════ R1. Refund Play ════
insert into public.topup_orders (id, user_id, package_id, coins, price_idr, status,
                                 provider, purchase_token, platform, paid_at)
values ('play_test_r1', 'ed0b0000-0000-4000-8000-0000000000a1',
        (select id from public.topup_packages order by price_idr limit 1),
        700, 10000, 'paid', 'play_billing', 'tok-test-r1', 'play',
        now() - interval '1 day');
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed0b0000-0000-4000-8000-0000000000a1', 'topup', 'topup', 700, 'play_test_r1');
-- Male sudah memakai 200 → sisa topup 500.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed0b0000-0000-4000-8000-0000000000a1', 'topup', 'call_video', -200, 'x');
insert into public.platform_revenue (source, amount, from_user, to_user, ref_id)
values ('call_video', 140, 'ed0b0000-0000-4000-8000-0000000000a1',
        'ed0b0000-0000-4000-8000-0000000000f1', 'x');

insert into _h values ('r1', public.reverse_play_topup('tok-test-r1', 'test')::text);
select supabase_tests.check('R1: reverse ok, shortfall 200, 2 akun ditahan',
  (select (v::jsonb->>'ok')::boolean from _h where k='r1') = true
  and (select (v::jsonb->>'shortfall')::int from _h where k='r1') = 200
  and (select (v::jsonb->>'flagged')::int from _h where k='r1') = 2,
  (select v from _h where k='r1'));
select supabase_tests.check('R1: saldo topup pembeli jadi 0 (tidak negatif)',
  (select coalesce(sum(amount), 0) from public.coin_ledger
    where user_id = 'ed0b0000-0000-4000-8000-0000000000a1' and bucket = 'topup') = 0);
select supabase_tests.check('R1: order → refunded',
  (select status from public.topup_orders where id = 'play_test_r1') = 'refunded');
insert into _h values ('r2', public.reverse_play_topup('tok-test-r1', 'test')::text);
select supabase_tests.check('R1: idempoten (already)',
  (select (v::jsonb->>'already')::boolean from _h where k='r2') = true);

select set_config('request.jwt.claim.sub', 'ed0b0000-0000-4000-8000-0000000000f1', true);
update public.withdrawal_requests set created_at = now() - interval '2 days'
 where user_id = 'ed0b0000-0000-4000-8000-0000000000f1';
insert into _h values ('r3', public.request_withdraw(2000)::text);
select supabase_tests.check('R1: penerima ditahan → UNDER_REVIEW',
  (select v::jsonb->>'error' from _h where k='r3') = 'UNDER_REVIEW',
  (select v from _h where k='r3'));
select supabase_tests.check('R1: reverse_play_topup tidak executable authenticated',
  has_function_privilege('authenticated', 'public.reverse_play_topup(text,text)', 'execute') = false);

-- ════ B1. Private call ditagih walau random_call mati ════
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed0b0000-0000-4000-8000-0000000000a1', 'topup', 'topup', 500, 'b1');
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ed0b0000-0000-4000-8000-0000000000c1'::uuid,
        'ed0b0000-0000-4000-8000-0000000000a1',
        'ed0b0000-0000-4000-8000-0000000000f1',
        'direct', 'video', 'answered', now() - interval '70 seconds');
select set_config('request.jwt.claim.sub', 'ed0b0000-0000-4000-8000-0000000000a1', true);
insert into _h values ('b1', public.call_billing_tick('ed0b0000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('B1: private call tetap ditagih (random_call mati)',
  (select (v::jsonb->>'billed_minutes')::int from _h where k='b1') = 2,
  (select v from _h where k='b1'));

-- ════ B2. Random tanpa media tersambung → 0 tagihan ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ed0b0000-0000-4000-8000-0000000000c2'::uuid,
        'ed0b0000-0000-4000-8000-0000000000a1',
        'ed0b0000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered', now() - interval '5 minutes');
update public.app_settings
   set feature_flags = feature_flags || '{"random_call":{"published":true}}'::jsonb
 where id = 'global';
insert into _h values ('b2', public.call_billing_tick('ed0b0000-0000-4000-8000-0000000000c2')::text);
select supabase_tests.check('B2: random tanpa media_connected_at → 0 menit',
  coalesce((select (v::jsonb->>'billed_minutes')::int from _h where k='b2'), 0) = 0
  and not exists (select 1 from public.yukcoin_consumptions
                  where ref_id = 'ed0b0000-0000-4000-8000-0000000000c2'),
  (select v from _h where k='b2'));
select supabase_tests.check('B3: metered_pricing_public berisi biaya match',
  (public.metered_pricing_public() ? 'match_search_cost')
  and (public.metered_pricing_public() ? 'match_connect_cost'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
