-- Lapis 4: koin GRATIS tidak boleh jadi uang (audit peredaran 2026-11-01).
--   L1  charge_metered / call_billing_tick → wajib koin beli/penghasilan
--   L2  request_withdraw → HANYA bucket earned
--   L3  claim_mission_reward → female: earned; selain female: bonus
-- Jalankan: scripts/run_sql_tests.sh economy_paid_only_test.sql
-- Transaksional — hanya akun dummy test; semua angka dari app_settings live.
begin;
select supabase_tests.begin_tests();
-- Masa tahan (20261109020000) diuji di withdraw_hold_refund_test; di sini 0
-- supaya saldo earned seed (dibuat "sekarang") bisa langsung ditarik.
update public.app_settings set withdraw_hold_days = 0 where id = 'global';

select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] PoM1', 'online');
select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] PoM2', 'online');
select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000a3'::uuid, '[TEST] PoF1', 'online');
select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000a4'::uuid, '[TEST] PoF2', 'online');
select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000a5'::uuid, '[TEST] PoF3', 'online');

-- Penuaan akun SEBELUM claim sub di-set (guard_economy_columns mengunci
-- created_at untuk permintaan client).
update public.profiles set gender = 'female',
       created_at = now() - interval '10 days'
 where id in ('ec05e000-0000-4000-8000-0000000000a3',
              'ec05e000-0000-4000-8000-0000000000a4',
              'ec05e000-0000-4000-8000-0000000000a5');

-- Dana: a1 topup 500 · a2 bonus-only 500 · a3 earned 2000 ·
-- a4 bonus-only 3000 · a5 earned 1000 + bonus 3000.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values
 ('ec05e000-0000-4000-8000-0000000000a1','topup','topup',500,'test-po'),
 ('ec05e000-0000-4000-8000-0000000000a2','bonus','admin_mass_bonus',500,'test-po'),
 ('ec05e000-0000-4000-8000-0000000000a3','earned','call_video_income',2000,'test-po'),
 ('ec05e000-0000-4000-8000-0000000000a4','bonus','admin_mass_bonus',3000,'test-po'),
 ('ec05e000-0000-4000-8000-0000000000a5','earned','call_video_income',1000,'test-po'),
 ('ec05e000-0000-4000-8000-0000000000a5','bonus','admin_mass_bonus',3000,'test-po');

create temp table _po (k text primary key, v text) on commit drop;
grant all on _po to service_role;

-- ════ 1. yukcoin_paid_total — cermin paidBalance client ════
select supabase_tests.check('paid_total: a1 topup 500 → 500',
  public.yukcoin_paid_total('ec05e000-0000-4000-8000-0000000000a1') = 500);
select supabase_tests.check('paid_total: a2 bonus-only → 0',
  public.yukcoin_paid_total('ec05e000-0000-4000-8000-0000000000a2') = 0);
select supabase_tests.check('paid_total: a5 earned 1000 + bonus 3000 → 1000',
  public.yukcoin_paid_total('ec05e000-0000-4000-8000-0000000000a5') = 1000);

-- ════ 2. charge_metered: koin beli cukup → sukses ════
insert into _po values ('m1',
  public.charge_metered('ec05e000-0000-4000-8000-0000000000a1',
                        'call_video', 'po-call-1', 1,
                        'ec05e000-0000-4000-8000-0000000000a3')::text);
select supabase_tests.check('L1: charge paid 20 → charged 20, cut 14 (70%)',
  (select (v::jsonb->>'charged')::int from _po where k='m1') = 20
  and (select (v::jsonb->>'cut')::int from _po where k='m1') = 14,
  (select v from _po where k='m1'));
select supabase_tests.check('L1: female +6 earned call_video_income',
  exists (select 1 from public.coin_ledger
          where user_id='ec05e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='call_video_income' and amount=6));
select supabase_tests.check('L1: caller topup −20 (bucket topup, bukan bonus)',
  exists (select 1 from public.coin_ledger
          where user_id='ec05e000-0000-4000-8000-0000000000a1'
            and bucket='topup' and type='call_video' and amount=-20));
select supabase_tests.check('L1: platform_revenue call_video 14',
  exists (select 1 from public.platform_revenue
          where source='call_video' and amount=14
            and from_user='ec05e000-0000-4000-8000-0000000000a1'));

-- ════ 3. charge_metered: BONUS-only → DITOLAK ════
do $$
begin
  perform public.charge_metered('ec05e000-0000-4000-8000-0000000000a2',
                                'call_video', 'po-call-2', 1,
                                'ec05e000-0000-4000-8000-0000000000a3');
  insert into _po values ('m2', 'lolos');
exception when others then
  insert into _po values ('m2', sqlerrm);
end $$;
select supabase_tests.check('L1: bonus-only charge → ditolak (butuh koin beli)',
  (select v from _po where k='m2') like '%Koin beli%',
  (select v from _po where k='m2'));
select supabase_tests.check('L1: bonus-only → female TIDAK dapat income',
  not exists (select 1 from public.coin_ledger
              where user_id='ec05e000-0000-4000-8000-0000000000a3'
                and type='call_video_income' and ref_id='po-call-2'));
select supabase_tests.check('L1: bonus-only → saldo bonus utuh (500)',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec05e000-0000-4000-8000-0000000000a2') = 500);

-- ════ 4. charge_metered: campuran → debit earned, bonus utuh ════
insert into _po values ('m3',
  public.charge_metered('ec05e000-0000-4000-8000-0000000000a5',
                        'call_audio', 'po-call-3', 1,
                        'ec05e000-0000-4000-8000-0000000000a3')::text);
select supabase_tests.check('L1: mixed charge audio 6 → charged 6',
  (select (v::jsonb->>'charged')::int from _po where k='m3') = 6,
  (select v from _po where k='m3'));
select supabase_tests.check('L1: mixed → earned −6 (994), bonus 3000 utuh',
  (select coalesce(sum(amount) filter (where bucket='earned'),0)
     from public.coin_ledger
    where user_id='ec05e000-0000-4000-8000-0000000000a5') = 994
  and (select coalesce(sum(amount) filter (where bucket='bonus'),0)
     from public.coin_ledger
    where user_id='ec05e000-0000-4000-8000-0000000000a5') = 3000);

-- ════ 5. call_billing_tick — afford pakai saldo paid ════
-- Flag call_billing harus published (live: false) agar tick tidak free-pass.
update public.app_settings
   set feature_flags = feature_flags || '{"call_billing":{"published":true}}'::jsonb
 where id = 'global';

-- 5a. caller bonus-only, call 5 menit → can_continue=false, tanpa debit.
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ec05e000-0000-4000-8000-0000000000c1'::uuid,
        'ec05e000-0000-4000-8000-0000000000a2',
        'ec05e000-0000-4000-8000-0000000000a3',
        'direct', 'video', 'answered', now() - interval '5 minutes');
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a2', true);
insert into _po values ('t1',
  public.call_billing_tick('ec05e000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('L1: tick bonus-only → can_continue=false (insufficient)',
  (select (v::jsonb->>'can_continue')::boolean from _po where k='t1') = false
  and (select v::jsonb->>'reason' from _po where k='t1') = 'insufficient',
  (select v from _po where k='t1'));
select supabase_tests.check('L1: tick bonus-only → TIDAK ada debit & income',
  not exists (select 1 from public.coin_ledger
              where user_id='ec05e000-0000-4000-8000-0000000000a2' and amount < 0)
  and not exists (select 1 from public.yukcoin_consumptions
                  where user_id='ec05e000-0000-4000-8000-0000000000a2'));

-- 5b. caller ber-koin beli, call 3 menit → tagih 3×20, female +18.
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ec05e000-0000-4000-8000-0000000000c2'::uuid,
        'ec05e000-0000-4000-8000-0000000000a1',
        'ec05e000-0000-4000-8000-0000000000a3',
        'direct', 'video', 'answered', now() - interval '3 minutes');
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a1', true);
insert into _po values ('t2',
  public.call_billing_tick('ec05e000-0000-4000-8000-0000000000c2')::text);
select supabase_tests.check('L1: tick paid → can_continue=true, billed 3 menit',
  (select (v::jsonb->>'can_continue')::boolean from _po where k='t2') = true
  and (select (v::jsonb->>'billed_minutes')::int from _po where k='t2') = 3
  and (select (v::jsonb->>'charged_total')::int from _po where k='t2') = 60,
  (select v from _po where k='t2'));
select supabase_tests.check('L1: tick paid → female +18 earned (30% dari 60)',
  exists (select 1 from public.coin_ledger
          where user_id='ec05e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='call_video_income' and amount=18));

-- ════ 6. request_withdraw: earned cukup → sukses ════
-- withdraw_min_coins live = 2000 (20261101160000).
-- Fase B: withdraw wajib KYC approved.
insert into public.kyc_requests (user_id, status, full_name, id_number,
                                 id_photo, selfie_photo)
values ('ec05e000-0000-4000-8000-0000000000a3', 'approved',
        '[TEST] F3', '3201xxxx', 'x', 'x');
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a3', true);
insert into _po values ('w1',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('L2: withdraw earned 2000 → ok',
  (select v::jsonb->>'ok' from _po where k='w1') = 'true',
  (select v from _po where k='w1'));
select supabase_tests.check('L2: debit −2000 bucket earned',
  exists (select 1 from public.coin_ledger
          where user_id='ec05e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='withdraw' and amount=-2000));

-- ════ 7. request_withdraw: BONUS-only → INSUFFICIENT ════
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a4', true);
insert into _po values ('w2',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('L2: female bonus-only 3000 → INSUFFICIENT_BALANCE',
  (select v::jsonb->>'error' from _po where k='w2') = 'INSUFFICIENT_BALANCE',
  (select v from _po where k='w2'));
select supabase_tests.check('L2: bonus-only → tanpa pengajuan, bonus utuh 3000',
  not exists (select 1 from public.withdrawal_requests
              where user_id='ec05e000-0000-4000-8000-0000000000a4')
  and (select coalesce(sum(amount),0) from public.coin_ledger
        where user_id='ec05e000-0000-4000-8000-0000000000a4') = 3000);

-- ════ 8. request_withdraw: total besar, earned kurang → tetap ditolak ════
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a5', true);
insert into _po values ('w3',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('L2: earned 994 < 2000 → INSUFFICIENT (total 3994 diabaikan)',
  (select v::jsonb->>'error' from _po where k='w3') = 'INSUFFICIENT_BALANCE',
  (select v from _po where k='w3'));
select supabase_tests.check('L2: mixed → bonus tetap utuh 3000',
  (select coalesce(sum(amount) filter (where bucket='bonus'),0)
     from public.coin_ledger
    where user_id='ec05e000-0000-4000-8000-0000000000a5') = 3000);

-- ════ 9. claim_mission_reward — bucket reward by gender ════
-- Misi 'like_posts' (gender all, reward 5, non-daily).
insert into public.user_missions (user_id, mission_id, progress, is_completed, period_date)
select 'ec05e000-0000-4000-8000-0000000000a1', m.id, 3, true, null
  from public.missions m where m.mission_key = 'like_posts';
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a1', true);
insert into _po values ('c1',
  public.claim_mission_reward('ec05e000-0000-4000-8000-0000000000a1',
                              'like_posts')::text);
select supabase_tests.check('L3: male klaim misi → bucket bonus',
  exists (select 1 from public.coin_ledger
          where user_id='ec05e000-0000-4000-8000-0000000000a1'
            and bucket='bonus' and type='mission_reward' and amount=5),
  (select v from _po where k='c1'));

insert into public.user_missions (user_id, mission_id, progress, is_completed, period_date)
select 'ec05e000-0000-4000-8000-0000000000a3', m.id, 3, true, null
  from public.missions m where m.mission_key = 'like_posts';
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a3', true);
insert into _po values ('c2',
  public.claim_mission_reward('ec05e000-0000-4000-8000-0000000000a3',
                              'like_posts')::text);
select supabase_tests.check('L3: female klaim misi → bucket bonus (tak bisa dicairkan)',
  exists (select 1 from public.coin_ledger
          where user_id='ec05e000-0000-4000-8000-0000000000a3'
            and bucket='bonus' and type='mission_reward' and amount=5),
  (select v from _po where k='c2'));

-- ════ 10. Regresi: klaim dobel tetap ditolak ════
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a1', true);
insert into _po values ('c3',
  public.claim_mission_reward('ec05e000-0000-4000-8000-0000000000a1',
                              'like_posts')::text);
select supabase_tests.check('L3: klaim kedua → ALREADY_CLAIMED',
  (select v::jsonb->>'error' from _po where k='c3') = 'ALREADY_CLAIMED',
  (select v from _po where k='c3'));

-- ════ 11. spend_yukcoin: client authenticated TIDAK boleh eksekusi ─═══
-- Pemanggil sah hanya random_match_join (definer) & service_role.
select supabase_tests.check('spend_yukcoin: authenticated tanpa EXECUTE',
  not has_function_privilege('authenticated',
    'public.spend_yukcoin(uuid,text,int,text,jsonb)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.spend_yukcoin(uuid,text,int,text,jsonb)', 'EXECUTE'));

-- ════ 12. get_earnings_summary: withdrawable = earned saja ════
-- a5 (female): earned 994 + bonus 3000 → withdrawable 994 (bukan 3994).
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000a5', true);
insert into _po values ('es',
  public.get_earnings_summary('ec05e000-0000-4000-8000-0000000000a5')::text);
select supabase_tests.check('earnings: withdrawable = earned 994 (bonus tak dihitung)',
  (select (v::jsonb->>'withdrawable')::int from _po where k='es') = 994,
  (select v from _po where k='es'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
