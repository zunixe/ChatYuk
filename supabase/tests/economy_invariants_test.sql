-- Lapis 3: invariant ekonomi — rekonsiliasi coin_ledger ↔ kolom cache
-- profiles (points, bonus_balance, topup_balance, earned_balance) dan
-- fungsi diagnostik public.economy_invariant_check.
-- Jalankan: scripts/run_sql_tests.sh economy_invariants_test.sql
-- Transaksional (begin/rollback) — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ec01e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] InvA', 'offline');
select supabase_tests.mk_dummy('ec01e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] InvB', 'offline');
select supabase_tests.mk_dummy('ec01e000-0000-4000-8000-0000000000a3'::uuid, '[TEST] InvC', 'offline');

-- ── 1. Trigger sync: insert ledger → kolom profile ikut ──
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values
 ('ec01e000-0000-4000-8000-0000000000a1','topup','topup',100,'test-inv'),
 ('ec01e000-0000-4000-8000-0000000000a1','bonus','admin_mass_bonus',50,'test-inv'),
 ('ec01e000-0000-4000-8000-0000000000a1','earned','gift_recv',30,'test-inv');

select supabase_tests.check('points = sum(ledger) setelah kredit',
  (select points from public.profiles
    where id = 'ec01e000-0000-4000-8000-0000000000a1') = 180);
select supabase_tests.check('bonus_balance = sum(bucket=bonus)',
  (select bonus_balance from public.profiles
    where id = 'ec01e000-0000-4000-8000-0000000000a1') = 50);
select supabase_tests.check('topup_balance = sum(bucket=topup)',
  (select topup_balance from public.profiles
    where id = 'ec01e000-0000-4000-8000-0000000000a1') = 100);
select supabase_tests.check('earned_balance = sum(bucket=earned)',
  (select earned_balance from public.profiles
    where id = 'ec01e000-0000-4000-8000-0000000000a1') = 30);

-- Debit ikut tersinkron.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ec01e000-0000-4000-8000-0000000000a1','earned','gift_sent',-10,'test-inv');
select supabase_tests.check('debit: earned_balance & points turun',
  (select earned_balance from public.profiles
    where id = 'ec01e000-0000-4000-8000-0000000000a1') = 20
  and (select points from public.profiles
    where id = 'ec01e000-0000-4000-8000-0000000000a1') = 170);

-- ── 2. Checker: akun sehat tidak dilaporkan ──
select supabase_tests.check('economy_invariant_check: dummy sehat → 0 pelanggaran',
  not exists (select 1 from public.economy_invariant_check(5000)
              where user_id = 'ec01e000-0000-4000-8000-0000000000a1'));

-- ── 3. Korupsi points → terdeteksi points_mismatch ──
update public.profiles set points = 999
 where id = 'ec01e000-0000-4000-8000-0000000000a1';
select supabase_tests.check('korupsi points → points_mismatch',
  exists (select 1 from public.economy_invariant_check(5000)
          where check_name = 'points_mismatch'
            and user_id = 'ec01e000-0000-4000-8000-0000000000a1'
            and expected = 170 and actual = 999));
update public.profiles set points = 170
 where id = 'ec01e000-0000-4000-8000-0000000000a1';

-- ── 4. Korupsi bonus_balance → bonus_mismatch ──
update public.profiles set bonus_balance = 0
 where id = 'ec01e000-0000-4000-8000-0000000000a1';
select supabase_tests.check('korupsi bonus → bonus_mismatch',
  exists (select 1 from public.economy_invariant_check(5000)
          where check_name = 'bonus_mismatch'
            and user_id = 'ec01e000-0000-4000-8000-0000000000a1'
            and expected = 50));

-- ── 5. Korupsi earned_balance → earned_mismatch ──
update public.profiles set earned_balance = 7
 where id = 'ec01e000-0000-4000-8000-0000000000a1';
select supabase_tests.check('korupsi earned → earned_mismatch',
  exists (select 1 from public.economy_invariant_check(5000)
          where check_name = 'earned_mismatch'
            and user_id = 'ec01e000-0000-4000-8000-0000000000a1'
            and expected = 20 and actual = 7));

-- ── 6. Saldo tanpa ledger → phantom_balance (dummy a2 tanpa ledger) ──
update public.profiles set points = 5
 where id = 'ec01e000-0000-4000-8000-0000000000a2';
select supabase_tests.check('saldo tanpa ledger → phantom_balance',
  exists (select 1 from public.economy_invariant_check(5000)
          where check_name = 'phantom_balance'
            and user_id = 'ec01e000-0000-4000-8000-0000000000a2'));

-- ── 7. Bucket negatif → negative_bucket ──
-- Sejak lockdown A4 guard nonneg menolak debit yang menjadikan bucket negatif;
-- invariant checker tetap safety-net untuk korupsi/manual edit → buat kondisi
-- itu dengan men-disable trigger sesaat (rollback membatalkan semuanya).
alter table public.coin_ledger disable trigger coin_ledger_nonneg_trg;
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ec01e000-0000-4000-8000-0000000000a3','earned','spend_chat',-25,'test-inv');
alter table public.coin_ledger enable trigger coin_ledger_nonneg_trg;
select supabase_tests.check('bucket earned negatif → negative_bucket',
  exists (select 1 from public.economy_invariant_check(5000)
          where check_name = 'negative_bucket'
            and user_id = 'ec01e000-0000-4000-8000-0000000000a3'
            and detail = 'bucket=earned'));

-- ── 8. Privilege: checker tidak bisa dieksekusi user ──
select supabase_tests.check('economy_invariant_check revoked dari authenticated',
  not has_function_privilege(
    'authenticated', 'public.economy_invariant_check(integer)', 'EXECUTE'));
select supabase_tests.check('economy_invariant_check revoked dari anon',
  not has_function_privilege(
    'anon', 'public.economy_invariant_check(integer)', 'EXECUTE'));
select supabase_tests.check('economy_invariant_check executable service_role',
  has_function_privilege(
    'service_role', 'public.economy_invariant_check(integer)', 'EXECUTE'));

select supabase_tests.report() as result;
rollback;
