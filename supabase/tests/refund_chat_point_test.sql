-- Lapis 3: refund_chat_point idempoten + jendela 10 menit (20261024100000).
-- Jalankan: scripts/run_sql_tests.sh refund_chat_point_test.sql
-- Transaksional (begin/rollback) — hanya akun dummy test, data produksi aman.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000c1'::uuid, '[TEST] RefundA', 'online');

-- Saldo awal 10, lalu spend 2 (text) sekarang.
select public.ledger_credit('d0c1e000-0000-4000-8000-0000000000c1'::uuid, 'bonus', '[TEST]', 10, '[TEST]', '{}'::jsonb);
select public.ledger_spend('d0c1e000-0000-4000-8000-0000000000c1'::uuid, 'spend_chat', 2, 'text');
-- Spend LAMA (1 jam lalu, image) — tidak boleh bisa di-refund.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id, created_at)
values ('d0c1e000-0000-4000-8000-0000000000c1', 'bonus', 'spend_chat', -3, 'image', now() - interval '1 hour');

select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000c1', true);

create temp table _rf (step text, bal int) on commit drop;
insert into _rf values ('awal', (select coalesce(sum(amount),0) from public.coin_ledger where user_id = 'd0c1e000-0000-4000-8000-0000000000c1'));
insert into _rf values ('refund1', public.refund_chat_point('text'));
insert into _rf values ('refund2', public.refund_chat_point('text'));
insert into _rf values ('refund3', public.refund_chat_point('text'));
insert into _rf values ('refund_lama', public.refund_chat_point('image'));

select supabase_tests.check('saldo awal = 10 - 2 - 3 = 5',
  (select bal from _rf where step = 'awal') = 5,
  (select bal::text from _rf where step = 'awal'));
select supabase_tests.check('refund pertama mengembalikan 2 → 7',
  (select bal from _rf where step = 'refund1') = 7,
  (select bal::text from _rf where step = 'refund1'));
select supabase_tests.check('refund kedua TIDAK menambah (idempoten)',
  (select bal from _rf where step = 'refund2') = 7,
  (select bal::text from _rf where step = 'refund2'));
select supabase_tests.check('refund ketiga TIDAK menambah',
  (select bal from _rf where step = 'refund3') = 7,
  (select bal::text from _rf where step = 'refund3'));
select supabase_tests.check('spend > 10 menit lalu tidak bisa di-refund',
  (select bal from _rf where step = 'refund_lama') = 7,
  (select bal::text from _rf where step = 'refund_lama'));
select supabase_tests.check('tepat 1 baris spend_refund tercatat',
  (select count(*) from public.coin_ledger
    where user_id = 'd0c1e000-0000-4000-8000-0000000000c1' and type = 'spend_refund') = 1);

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.check('tanpa auth.uid() → 0, tidak error',
  public.refund_chat_point('text') = 0);

select supabase_tests.report() as result;
rollback;
