-- pgTAP: bonus, saldo & withdraw — mengunci perbaikan audit 2026-11-01.
--
-- Menutup:
--   1. Female caller GRATIS (30 menit/hari) — dulu client memblokir.
--   2. claim_mission_reward untuk misi bertarget koin (nyonya_1000):
--      kelulusan dari saldo earned, klaim atomik, tidak bisa dobel.
--   3. Withdraw: kuota harian & cooldown TIDAK menghitung request `rejected`.
--   4. get_earnings_summary: match_call terpisah dari private_call.
--
-- Transaksional (BEGIN/ROLLBACK) — tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();
-- Masa tahan (20261109020000) diuji di withdraw_hold_refund_test; di sini 0
-- supaya saldo earned seed (dibuat "sekarang") bisa langsung ditarik.
update public.app_settings set withdraw_hold_days = 0 where id = 'global';

create temp table _gw (key text primary key, val text) on commit drop;
grant all on _gw to service_role;

select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000c1'::uuid,
                               '[TEST] BonusMale', 'online');
select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000c2'::uuid,
                               '[TEST] BonusFemale', 'online');
update public.profiles set gender = 'female',
       created_at = now() - interval '10 days'
 where id = 'ec05e000-0000-4000-8000-0000000000c2';

-- ════ 1. FEMALE CALLER GRATIS ════
-- Female memanggil male: server harus mengizinkan lanjut & tidak menagih.
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c2', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);

insert into public.calls (id, caller_id, callee_id, call_type, status, kind,
                          answered_at, last_seen_at)
values ('ec05e000-0000-4000-8000-0000000000f1'::uuid,
        'ec05e000-0000-4000-8000-0000000000c2',
        'ec05e000-0000-4000-8000-0000000000c1',
        'video', 'answered', 'direct', now(), now());

insert into _gw(key, val)
  select 'female_tick',
         public.call_billing_tick('ec05e000-0000-4000-8000-0000000000f1'::uuid)::text;

select supabase_tests.check('female caller: can_continue true',
  (select (val::jsonb->>'can_continue') from _gw
    where key = 'female_tick') = 'true');
select supabase_tests.check('female caller: charged_total 0',
  (select coalesce((val::jsonb->>'charged_total')::int, -1)
     from _gw where key = 'female_tick') = 0);
select supabase_tests.check('female caller: tidak ada baris ledger charge',
  not exists (select 1 from public.coin_ledger
               where user_id = 'ec05e000-0000-4000-8000-0000000000c2'
                 and type in ('call_audio','call_video')));

-- ════ 2. MISI BERTARGET KOIN (nyonya_1000) ════
-- Female dengan earned >= 1000 → klaim sukses, satu baris ledger.
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
values ('ec05e000-0000-4000-8000-0000000000c2','earned','test_seed',1200,'gw-seed');

insert into _gw(key, val)
  select 'nyonya_claim',
         public.claim_mission_reward(
           'ec05e000-0000-4000-8000-0000000000c2', 'nyonya_1000')::text;

select supabase_tests.check('nyonya_1000: klaim sukses',
  (select (val::jsonb->>'success') from _gw
    where key = 'nyonya_claim') = 'true');
select supabase_tests.check('nyonya_1000: tepat 1 baris mission_reward',
  (select count(*) from public.coin_ledger
    where user_id = 'ec05e000-0000-4000-8000-0000000000c2'
      and type = 'mission_reward') = 1);

-- Klaim kedua → ditolak (anti dobel).
insert into _gw(key, val)
  select 'nyonya_reclaim',
         public.claim_mission_reward(
           'ec05e000-0000-4000-8000-0000000000c2', 'nyonya_1000')::text;
select supabase_tests.check('nyonya_1000: klaim kedua → ALREADY_CLAIMED',
  (select (val::jsonb->>'error') from _gw
    where key = 'nyonya_reclaim') = 'ALREADY_CLAIMED');
select supabase_tests.check('nyonya_1000: tetap 1 baris setelah klaim ulang',
  (select count(*) from public.coin_ledger
    where user_id = 'ec05e000-0000-4000-8000-0000000000c2'
      and type = 'mission_reward') = 1);

-- Female dengan earned < target → tidak bisa klaim.
-- (Misi ini female-only; male dapat MISSION_NOT_STARTED — diuji terpisah.)
select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000c3'::uuid,
                               '[TEST] BonusF3', 'online');
update public.profiles set gender = 'female'
 where id = 'ec05e000-0000-4000-8000-0000000000c3';
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c3', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c3","role":"authenticated"}', true);

insert into _gw(key, val)
  select 'nyonya_poor',
         public.claim_mission_reward(
           'ec05e000-0000-4000-8000-0000000000c3', 'nyonya_1000')::text;
select supabase_tests.check('nyonya_1000: saldo kurang → MISSION_NOT_COMPLETED',
  (select (val::jsonb->>'error') from _gw
    where key = 'nyonya_poor') = 'MISSION_NOT_COMPLETED');

select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c1', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
insert into _gw(key, val)
  select 'nyonya_male',
         public.claim_mission_reward(
           'ec05e000-0000-4000-8000-0000000000c1', 'nyonya_1000')::text;
-- Kembalikan sub ke female untuk bagian withdraw di bawah.
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c2', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
-- 2026-11-02: guard gender misi ditambahkan di server → male dapat
-- MISSION_NOT_FOUND (bukan MISSION_NOT_COMPLETED). Uji lengkap untuk male
-- dengan saldi besar ada di bagian 7 di bawah.
select supabase_tests.check('nyonya_1000: male → ditolak (guard gender)',
  (select (val::jsonb->>'error') from _gw
    where key = 'nyonya_male') in ('MISSION_NOT_COMPLETED','MISSION_NOT_FOUND'));

-- ════ 3. WITHDRAW: rejected tidak menghabiskan kuota ════
-- Satu request ditolak, lalu request baru harus tetap boleh (bukan
-- DAILY_LIMIT / TOO_SOON).
-- Saldo earned cukup dulu (server menolak bonus; request butuh earned).
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
values ('ec05e000-0000-4000-8000-0000000000c2','earned','test_seed',9000,'gw-wd-seed');

insert into public.withdraw_accounts(user_id, dana_number, dana_name)
values ('ec05e000-0000-4000-8000-0000000000c2','081234567890','[TEST] Dana')
on conflict (user_id) do update set dana_number = excluded.dana_number;
-- Fase B: withdraw wajib KYC approved.
insert into public.kyc_requests (user_id, status, full_name, id_number,
                                 id_photo, selfie_photo)
values ('ec05e000-0000-4000-8000-0000000000c2', 'approved',
        '[TEST] C2', '3201xxxx', 'x', 'x');

-- ISI KUOTA PENUH dengan baris `rejected`: kalau filter
-- `status <> 'rejected'` hilang, request baru akan kena DAILY_LIMIT.
-- (Satu baris saja tidak cukup — kuota harian 3, jadi lolos dua-duanya.)
do $$
declare i int;
begin
  for i in 1..3 loop
    insert into public.withdrawal_requests
      (user_id, coin_amount, payout_idr, gross_idr, fee_idr, rate, status,
       pay_method, pay_account, pay_holder)
    values ('ec05e000-0000-4000-8000-0000000000c2', 2000, 13000, 14000, 1000, 7,
            'rejected', 'ewallet', '081234567890', '[TEST] Dana');
  end loop;
end $$;

select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
insert into _gw(key, val)
  select 'wd_reject',
         public.admin_withdraw_process(
           (select id from public.withdrawal_requests
             where user_id = 'ec05e000-0000-4000-8000-0000000000c2'
               and status = 'rejected' limit 1),
           false, '[TEST] tolak')::text;
select set_config('request.jwt.claim.email', '', true);

select supabase_tests.check('reject baris sudah-rejected → ALREADY_PROCESSED',
  (select (val::jsonb->>'error') from _gw
    where key = 'wd_reject') = 'ALREADY_PROCESSED');

-- Request BARU setelah ada yang rejected → harus lolos gate kuota.
-- PENTING: jumlahnya harus >= withdraw_min_coins (live: 2000). Kalau kurang,
-- server balas BELOW_MINIMUM SEBELUM sampai ke logika kuota → assertion
-- di bawah lulus kosong dan tidak menguji apa pun (persis yang terjadi
-- saat file ini pertama ditulis dengan 1500).
do $$
declare
  v_min int;
begin
  select coalesce(withdraw_min_coins, 1500) into v_min
    from public.app_settings where id = 'global';
  insert into _gw(key, val)
    select 'wd_new',
           public.request_withdraw(v_min)::text;
end $$;

-- Assertion POSITIF: request harus BERHASIL, bukan cuma "bukan DAILY_LIMIT".
-- Ini yang menangkap regresi bila filter `status <> 'rejected'` hilang lagi.
select supabase_tests.check('request setelah reject → BERHASIL (kuota tak terpakai)',
  (select (val::jsonb->>'ok') from _gw
    where key = 'wd_new') = 'true');

-- Dan pastikan benar-benar ada baris pending baru (bukan false positive).
select supabase_tests.check('request setelah reject → baris pending tercatat',
  exists (select 1 from public.withdrawal_requests
           where user_id = 'ec05e000-0000-4000-8000-0000000000c2'
             and status = 'pending'));

-- ════ 4. get_earnings_summary: match_call terpisah ════
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
values ('ec05e000-0000-4000-8000-0000000000c2','earned','match_call_income',500,'gw-mc'),
       ('ec05e000-0000-4000-8000-0000000000c2','earned','call_video_income',300,'gw-pc');

insert into _gw(key, val)
  select 'earnings',
         public.get_earnings_summary('ec05e000-0000-4000-8000-0000000000c2')::text;

select supabase_tests.check('earnings: match_call = 500 (terpisah)',
  (select ((val::jsonb->'breakdown')->>'match_call')::int
     from _gw where key = 'earnings') = 500);
select supabase_tests.check('earnings: private_call = 300 (tanpa match)',
  (select ((val::jsonb->'breakdown')->>'private_call')::int
     from _gw where key = 'earnings') = 300);

-- Guard anti-IDOR tetap berlaku: memanggil dengan uid ORANG LAIN harus
-- mengembalikan 42501, bukan data.
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c1', true);
do $$
begin
  perform public.get_earnings_summary('ec05e000-0000-4000-8000-0000000000c2');
  insert into _gw values ('idor', 'BOCOR');
exception
  when others then
    insert into _gw values ('idor', sqlstate);
end $$;
select supabase_tests.check('get_earnings_summary: uid orang lain ditolak (42501)',
  (select val from _gw where key = 'idor') = '42501');

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.email', '', true);


-- ══════════════════════════════════════════════════════════════════
-- BAGIAN TAMBAHAN (2026-11-02): menutup perilahan yang TIDAK ada tesnya
-- ══════════════════════════════════════════════════════════════════

-- ── 5. Batas gratis female 30 menit/hari ──
-- Female memanggil male: gratis sampai batas; setelah itu can_continue=false.
-- Sebelumnya hanya jalur DI BAWAH batas yang diuji.
-- CATATAN: `call_billing` harus published, kalau tidak call_billing_tick
-- kelang lebih awal (free-pass) dan cabang batas gratis tidak pernah tercapai.
-- Pastikan flag call_billing published (default live: false).
update public.app_settings
   set feature_flags = jsonb_set(
         coalesce(feature_flags, '{}'::jsonb),
         '{call_billing,published}', 'true'::jsonb)
 where id = 'global';

select supabase_tests.mk_dummy('ec05e000-0000-4000-8000-0000000000d1'::uuid,
                               '[TEST] FreeLimitF', 'online');
update public.profiles set gender = 'female'
 where id = 'ec05e000-0000-4000-8000-0000000000d1';

-- Habiskan kuota gratis: 3 panggilan × 10 menit = 30 menit ke callee male.
do $$
declare i int;
begin
  for i in 1..3 loop
    insert into public.calls (id, caller_id, callee_id, call_type, status, kind,
                              answered_at, ended_at, last_seen_at)
    values (
      ('ec05e000-0000-4000-8000-00000000e0' || lpad(i::text, 2, '0'))::uuid,
      'ec05e000-0000-4000-8000-0000000000d1',
      'ec05e000-0000-4000-8000-0000000000c1',
      'video', 'ended', 'direct',
      -- 10 menit/call; dekat ke now() supaya tetap "hari ini" (WIB) walau
      -- test jalan sesaat setelah tengah malam (dulu −40 m → gagal 00:00–00:40).
      now() - interval '11 minutes',
      now() - interval '1 minute',
      now() - interval '1 minute'
    );
  end loop;
end $$;

insert into public.calls (id, caller_id, callee_id, call_type, status, kind,
                          answered_at, last_seen_at)
values ('ec05e000-0000-4000-8000-00000000e099'::uuid,
        'ec05e000-0000-4000-8000-0000000000d1',
        'ec05e000-0000-4000-8000-0000000000c1',
        'video', 'answered', 'direct', now(), now());

select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000d1', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);

insert into _gw(key, val)
  select 'free_limit',
         public.call_billing_tick('ec05e000-0000-4000-8000-00000000e099'::uuid)::text;
select supabase_tests.check('female: kuota gratis habis → can_continue false',
  (select (val::jsonb->>'can_continue') from _gw
    where key = 'free_limit') = 'false');
select supabase_tests.check('female: alasan free_limit',
  (select (val::jsonb->>'reason') from _gw
    where key = 'free_limit') = 'free_limit');
select supabase_tests.check('female: tetap tidak ada tagihan ledger',
  not exists (select 1 from public.coin_ledger
               where user_id = 'ec05e000-0000-4000-8000-0000000000d1'
                 and type in ('call_audio','call_video')));

-- ── 6. Kuota withdraw: batas tepat minimum ──
-- 1999 → BELOW_MINIMUM; 2000 (minimum live) → lolos gate minimum.
select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c2', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);

do $$
declare v_min int;
begin
  select coalesce(withdraw_min_coins, 1500) into v_min
    from public.app_settings where id = 'global';
  insert into _gw(key, val)
    select 'wd_below', public.request_withdraw(v_min - 1)::text;
  insert into _gw(key, val)
    select 'wd_at_min', public.request_withdraw(v_min)::text;
end $$;

select supabase_tests.check('withdraw (min-1) → BELOW_MINIMUM',
  (select (val::jsonb->>'error') from _gw where key = 'wd_below')
    = 'BELOW_MINIMUM');
select supabase_tests.check('withdraw (min) → TIDAK BELOW_MINIMUM',
  (select coalesce((val::jsonb->>'error'), 'NONE') from _gw
    where key = 'wd_at_min') <> 'BELOW_MINIMUM');

-- ── 7. Misi female-only: male tidak bisa klaim lewat RPC ──
-- nyonya_1000 difilter female hanya di UI; server sekarang menegakkannya.
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
values ('ec05e000-0000-4000-8000-0000000000c1','earned','test_seed',5000,'gw-male-nyonya');

select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c1', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);

insert into _gw(key, val)
  select 'nyonya_male_rich',
         public.claim_mission_reward(
           'ec05e000-0000-4000-8000-0000000000c1', 'nyonya_1000')::text;
select supabase_tests.check('nyonya_1000: male dengan earned 5000 → ditolak',
  (select (val::jsonb->>'error') from _gw
    where key = 'nyonya_male_rich') = 'MISSION_NOT_FOUND');
select supabase_tests.check('nyonya_1000: tidak ada baris reward untuk male',
  not exists (select 1 from public.coin_ledger
               where user_id = 'ec05e000-0000-4000-8000-0000000000c1'
                 and type = 'mission_reward'));

-- ── 8. get_earnings_summary: withdrawable = earned saja ──
-- Female c2 punya earned (dari misi nyonya + income) DAN bonus historis.
-- `withdrawable` harus hanya earned; `total_balance` mencakup semuanya.
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
values ('ec05e000-0000-4000-8000-0000000000c2','bonus','test_seed',777,'gw-bonus-hist');

select set_config('request.jwt.claim.sub',
                  'ec05e000-0000-4000-8000-0000000000c2', true);
select set_config('request.jwt.claims',
  '{"sub":"ec05e000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);

insert into _gw(key, val)
  select 'earn2',
         public.get_earnings_summary('ec05e000-0000-4000-8000-0000000000c2')::text;
select supabase_tests.check('withdrawable = earned saja (tanpa bonus)',
  (select (val::jsonb->>'withdrawable')::int from _gw where key = 'earn2')
  = (select coalesce(sum(amount),0) from public.coin_ledger
      where user_id = 'ec05e000-0000-4000-8000-0000000000c2'
        and bucket = 'earned'));
select supabase_tests.check('total_balance = semua bucket',
  (select (val::jsonb->>'total_balance')::int from _gw where key = 'earn2')
  = (select coalesce(sum(amount),0) from public.coin_ledger
      where user_id = 'ec05e000-0000-4000-8000-0000000000c2'));

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.email', '', true);
select supabase_tests.report() as result;
rollback;
