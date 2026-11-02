-- Lapis 3: aritmetika uang — fee/cut/revenue, bucket order, withdraw
-- (debit saat request + refund saat reject), topup idempoten, rate-limit,
-- match race (kandidat miskin diskip → kandidat funded ditagih sekali).
-- Jalankan: scripts/run_sql_tests.sh economy_money_test.sql
-- Transaksional — hanya akun dummy test; semua angka dari app_settings live.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ec03e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] MonM1', 'online');
select supabase_tests.mk_dummy('ec03e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] MonM2', 'online');
select supabase_tests.mk_dummy('ec03e000-0000-4000-8000-0000000000a3'::uuid, '[TEST] MonF1', 'online');
select supabase_tests.mk_dummy('ec03e000-0000-4000-8000-0000000000a4'::uuid, '[TEST] MonF2', 'online');
select supabase_tests.mk_dummy('ec03e000-0000-4000-8000-0000000000a5'::uuid, '[TEST] MonF3', 'online');
-- a6: male MISKIN permanen (tak pernah didanai) — untuk race §9.
-- Jangan pakai delete ledger (trigger coin_ledger_no_delete menolak).
select supabase_tests.mk_dummy('ec03e000-0000-4000-8000-0000000000a6'::uuid, '[TEST] MonM3', 'online');

update public.profiles set gender = 'female',
       created_at = now() - interval '10 days'
 where id in ('ec03e000-0000-4000-8000-0000000000a3',
              'ec03e000-0000-4000-8000-0000000000a4',
              'ec03e000-0000-4000-8000-0000000000a5');
update public.profiles set subscription_price = 100
 where id = 'ec03e000-0000-4000-8000-0000000000a4';

insert into public.private_chats (chat_id, participants) values
 ('[TEST]-mn-m1f1', array['ec03e000-0000-4000-8000-0000000000a1',
                          'ec03e000-0000-4000-8000-0000000000a3']::uuid[]),
 ('[TEST]-mn-m2f1', array['ec03e000-0000-4000-8000-0000000000a2',
                          'ec03e000-0000-4000-8000-0000000000a3']::uuid[]);
insert into public.user_photos (id, user_id, photo) values
 ('ec03e000-0000-4000-8000-0000000000f1',
  'ec03e000-0000-4000-8000-0000000000a5', '[TEST] photo');

-- Dana: m1 topup 500 + earned 100 + bonus 100; m2 bonus only 100.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values
 ('ec03e000-0000-4000-8000-0000000000a1','topup','topup',500,'test-mn'),
 ('ec03e000-0000-4000-8000-0000000000a1','earned','call_video_income',100,'test-mn'),
 ('ec03e000-0000-4000-8000-0000000000a1','bonus','admin_mass_bonus',100,'test-mn'),
 ('ec03e000-0000-4000-8000-0000000000a2','bonus','admin_mass_bonus',100,'test-mn'),
 ('ec03e000-0000-4000-8000-0000000000a3','earned','call_video_income',2000,'test-mn');

create temp table _mn (k text primary key, v text) on commit drop;
grant all on _mn to service_role;

-- ════ 1. GIFT: gross/cut/net + platform_revenue + earned penerima ════
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a1', true);
insert into _mn values ('gift',
  public.send_gift('[TEST]-mn-m1f1',
    'ec03e000-0000-4000-8000-0000000000a3', 'rose')::text);
select supabase_tests.check('gift rose 10: gross=10 cut=3 net=7 (30%)',
  (select (v::jsonb->>'gross')::int from _mn where k='gift') = 10
  and (select (v::jsonb->>'cut')::int from _mn where k='gift') = 3
  and (select (v::jsonb->>'net')::int from _mn where k='gift') = 7,
  (select v from _mn where k='gift'));
select supabase_tests.check('gift: pengirim topup −10 (bukan bonus)',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a1'
            and bucket='topup' and type='gift_sent' and amount=-10));
select supabase_tests.check('gift: penerima earned +7 gift_recv',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='gift_recv' and amount=7));
select supabase_tests.check('gift: platform_revenue gift_cut 3',
  exists (select 1 from public.platform_revenue
          where source='gift_cut' and amount=3
            and from_user='ec03e000-0000-4000-8000-0000000000a1'
            and to_user='ec03e000-0000-4000-8000-0000000000a3'));

-- ════ 2. GIFT wajib koin beli: bonus-only ditolak ════
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a2', true);
do $$
begin
  perform public.send_gift('[TEST]-mn-m2f1',
    'ec03e000-0000-4000-8000-0000000000a3', 'rose');
  insert into _mn values ('gift_bonus', 'lolos');
exception when others then
  insert into _mn values ('gift_bonus', sqlerrm);
end $$;
select supabase_tests.check('gift saldo bonus-only → ditolak (koin beli saja)',
  (select v from _mn where k='gift_bonus') like '%koin beli%',
  (select v from _mn where k='gift_bonus'));

-- ════ 3. SEND_COINS transfer penuh (tanpa cut) ════
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a1', true);
select public.send_coins('[TEST]-mn-m1f1',
  'ec03e000-0000-4000-8000-0000000000a3', 20);
select supabase_tests.check('send_coins 20: pengirim topup −20, penerima earned +20',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a1'
            and bucket='topup' and type='coin_sent' and amount=-20)
  and exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='coin_received' and amount=20));

-- ════ 4. RATE LIMIT coin_tx_max_per_hour ════
-- m1 sudah punya 2 tx (gift_sent + coin_sent). Set max=3 → 1 lagi lolos,
-- berikutnya ditolak.
update public.app_settings set coin_tx_max_per_hour = 3 where id = 'global';
select public.send_coins('[TEST]-mn-m1f1',
  'ec03e000-0000-4000-8000-0000000000a3', 5);
select supabase_tests.check('rate limit: tx ke-3 masih lolos',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a1'
            and type='coin_sent' and amount=-5));
do $$
begin
  perform public.send_coins('[TEST]-mn-m1f1',
    'ec03e000-0000-4000-8000-0000000000a3', 5);
  insert into _mn values ('rl', 'lolos');
exception when others then
  insert into _mn values ('rl', sqlerrm);
end $$;
select supabase_tests.check('rate limit: tx ke-4 → Too many transactions',
  (select v from _mn where k='rl') like '%Too many transactions%',
  (select v from _mn where k='rl'));
update public.app_settings set coin_tx_max_per_hour = 30 where id = 'global';

-- ════ 5. SUBSCRIBE: split + expiry ════
insert into _mn values ('sub',
  public.subscribe_creator('ec03e000-0000-4000-8000-0000000000a4', 1)::text);
select supabase_tests.check('subscribe 100: cut=30 (30%), net=70',
  (select (v::jsonb->>'cut')::int from _mn where k='sub') = 30
  and (select (v::jsonb->>'net')::int from _mn where k='sub') = 70,
  (select v from _mn where k='sub'));
select supabase_tests.check('subscribe: kreator earned +70 subscribe_income',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a4'
            and bucket='earned' and type='subscribe_income' and amount=70));
select supabase_tests.check('subscribe: platform_revenue subscribe_cut 30',
  exists (select 1 from public.platform_revenue
          where source='subscribe_cut' and amount=30
            and from_user='ec03e000-0000-4000-8000-0000000000a1'));
select supabase_tests.check('subscribe: baris subscription +30 hari',
  exists (select 1 from public.subscriptions
          where subscriber_id='ec03e000-0000-4000-8000-0000000000a1'
            and creator_id='ec03e000-0000-4000-8000-0000000000a4'
            and expires_at > now() + interval '29 days'));

-- ════ 6. WITHDRAW: fee math + DEBIT saat request + REFUND saat reject ════
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a3', true);
insert into _mn values ('wd',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('withdraw 2000@7: gross=14000 fee=1000 net=13000',
  (select (v::jsonb->>'gross_idr')::int from _mn where k='wd') = 14000
  and (select (v::jsonb->>'fee_idr')::int from _mn where k='wd') = 1000
  and (select (v::jsonb->>'net_idr')::int from _mn where k='wd') = 13000,
  (select v from _mn where k='wd'));
select supabase_tests.check('withdraw: saldo DIDEBIT −2000 saat request',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec03e000-0000-4000-8000-0000000000a3'
      and type='withdraw') = -2000);
select supabase_tests.check('withdraw: row pending tercatat',
  exists (select 1 from public.withdrawal_requests
          where user_id='ec03e000-0000-4000-8000-0000000000a3'
            and coin_amount=2000 and status='pending'));

-- Reject → refund penuh. WAJIB lewat admin_withdraw_process — itu fungsi
-- yang benar-benar dipanggil app (admin_withdrawal_review sudah di-revoke
-- sejak 20260819140000, jadi test lama menguji fungsi mati).
select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
select public.admin_withdraw_process(
  (select id from public.withdrawal_requests
    where user_id='ec03e000-0000-4000-8000-0000000000a3' and status='pending'
    limit 1),
  false, '[TEST] reject');
select set_config('request.jwt.claim.email', '', true);
select supabase_tests.check('withdraw reject → withdraw_refund +2000 earned',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='withdraw_refund' and amount=2000));
-- f1 = 2000 awal + 7 gift_recv + 20 coin_received + 5 rate-limit = 2032
-- (dihitung ulang setelah refund; bagian ini ada SEBELUM §7/§8).
select supabase_tests.check('withdraw reject → saldo kembali 2032',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec03e000-0000-4000-8000-0000000000a3') = 2032);

-- ════ 7. UNLOCK_PHOTO — FITUR DINONAKTIFKAN 2026-11-01 ════
-- Test lama dihapus: `unlock_photo` sudah dicabut EXECUTE-nya dari
-- authenticated (20261101200000) dan tidak ada UI yang memanggilnya.
-- Menyimpan test untuk fungsi mati hanya menyesatkan developer berikutnya.
-- (income foto `photo_income` karena itu juga tidak lagi bisa terjadi.)

-- ════ 8. CHARGE_METERED: harga kolom + income female (male tidak) ════
-- call_video 20/min, cut 70% → caller −20, female +6, revenue 14.
insert into _mn values ('metered',
  public.charge_metered('ec03e000-0000-4000-8000-0000000000a1',
                        'call_video', 'mn-call', 1,
                        'ec03e000-0000-4000-8000-0000000000a3')::text);
select supabase_tests.check('charge_metered: charged 20 sesuai kolom',
  (select (v::jsonb->>'charged')::int from _mn where k='metered') = 20
  and (select (v::jsonb->>'cut')::int from _mn where k='metered') = 14,
  (select v from _mn where k='metered'));
select supabase_tests.check('charge_metered: female +6 call_video_income',
  exists (select 1 from public.coin_ledger
          where user_id='ec03e000-0000-4000-8000-0000000000a3'
            and bucket='earned' and type='call_video_income' and amount=6));
select supabase_tests.check('charge_metered: platform_revenue call_video 14',
  exists (select 1 from public.platform_revenue
          where source='call_video' and amount=14
            and from_user='ec03e000-0000-4000-8000-0000000000a1'));
-- Recipient male → tidak ada income (platform ambil semua net).
insert into _mn values ('metered_m',
  public.charge_metered('ec03e000-0000-4000-8000-0000000000a1',
                        'call_video', 'mn-call2', 1,
                        'ec03e000-0000-4000-8000-0000000000a2')::text);
select supabase_tests.check('charge_metered: recipient male → tanpa income',
  not exists (select 1 from public.coin_ledger
              where user_id='ec03e000-0000-4000-8000-0000000000a2'
                and type='call_video_income'));

-- ════ 9. MATCH RACE: kandidat male miskin diskip, funded ditagih sekali ════
update public.app_settings
   set feature_flags = feature_flags || '{"random_call":{"published":true}}'::jsonb
 where id = 'global';
-- a6 (0 koin): join → no_funds (precheck), tak masuk antrean.
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a6', true);
insert into _mn values ('m3_join',
  public.random_match_join('all')::text);
select supabase_tests.check('race: male 0 koin join → no_funds',
  (select v::jsonb->>'status' from _mn where k='m3_join') = 'no_funds');
-- Masukkan a6 ke antrean manual mensimulasikan antrean lama (bypass gate).
insert into public.random_match_queue
  (user_id, gender, want_gender, lat, lon, pinged_at)
values ('ec03e000-0000-4000-8000-0000000000a6','male','female',
        -6.20, 106.80, now());
-- m1 funded join → waiting (butuh female).
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a1', true);
insert into _mn values ('m1_join',
  public.random_match_join('all')::text);
-- f1 join → match dengan kandidat funded terdekat; m2 (0) diskip.
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a3', true);
insert into _mn values ('f1_join',
  public.random_match_join('all')::text);
select supabase_tests.check('race: female match dengan male funded (bukan miskin)',
  (select v::jsonb->>'status' from _mn where k='f1_join') = 'matched'
  and (select v::jsonb->'partner'->>'uid' from _mn where k='f1_join')
      = 'ec03e000-0000-4000-8000-0000000000a1',
  (select v from _mn where k='f1_join'));
select supabase_tests.check('race: match_search −2 tepat SEKALI dari m1',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec03e000-0000-4000-8000-0000000000a1'
      and type='match_search') = -2);
select supabase_tests.check('race: a6 tidak didebit & tidak ter-pair',
  not exists (select 1 from public.coin_ledger
              where user_id='ec03e000-0000-4000-8000-0000000000a6'
                and type='match_search'));

-- ════ 10. TOPUP IDEMPOTEN: provider_ref sama → kredit sekali ════
insert into public.topup_orders
  (id, user_id, package_id, coins, price_idr, status, provider)
values ('test-ord-1', 'ec03e000-0000-4000-8000-0000000000a1',
        'pkg_10k', 700, 10000, 'pending', 'play');
select public.credit_topup_order('test-ord-1','paid','ref-abc','{}');
insert into _mn values ('topup2',
  public.credit_topup_order('test-ord-1','paid','ref-abc','{}')::text);
select supabase_tests.check('topup ulang → already:true, ledger hanya 1 baris',
  (select v::jsonb->>'already' from _mn where k='topup2') = 'true'
  and (select count(*) from public.coin_ledger
        where user_id='ec03e000-0000-4000-8000-0000000000a1'
          and type='topup' and ref_id='test-ord-1') = 1);

-- ════ 11. BUCKET ORDER: spend_yukcoin = earned dulu lalu bonus ════
-- m1: earned sisa 98 setelah race §9 (−2), bonus 60 setelah metered §8
-- (−40 via ledger_spend bonus-first). Spend 150 → earned −98, bonus −52.
-- (sum() di assert = −100 earned, −52 bonus termasuk race −2.)
select set_config('request.jwt.claim.sub', 'ec03e000-0000-4000-8000-0000000000a1', true);
insert into _mn values ('spend_ord',
  public.spend_yukcoin('ec03e000-0000-4000-8000-0000000000a1',
                       'match_search', 150, 'mn')::text);
select supabase_tests.check('spend_yukcoin: earned −100 dulu, bonus −50',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec03e000-0000-4000-8000-0000000000a1'
      and bucket='earned' and type='match_search') = -100
  and (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec03e000-0000-4000-8000-0000000000a1'
      and bucket='bonus' and type='match_search') = -52,
  (select v from _mn where k='spend_ord'));

-- ════ 12. Sehat menyeluruh: invariant check untuk semua dummy ════
select supabase_tests.check('invariant: semua akun test tetap konsisten',
  not exists (select 1 from public.economy_invariant_check(5000)
              where user_id in
              ('ec03e000-0000-4000-8000-0000000000a1',
               'ec03e000-0000-4000-8000-0000000000a2',
               'ec03e000-0000-4000-8000-0000000000a3',
               'ec03e000-0000-4000-8000-0000000000a4',
               'ec03e000-0000-4000-8000-0000000000a5',
               'ec03e000-0000-4000-8000-0000000000a6')));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
