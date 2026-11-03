-- Lapis 4: Random-match billing hybrid (20261103100000).
--   Payer = SELALU pihak male siapa pun caller signaling-nya.
--   Gratis 30 detik → biaya konek 10 (female +3) → 20/menit (female +6).
--   <30 detik siapa pun yang tutup → male hanya rugi pair fee (di match_join).
-- Jalankan: scripts/run_sql_tests.sh match_billing_test.sql
-- Transaksional — hanya akun dummy test; angka dari app_settings live.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ec06e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] MBM1', 'online');
select supabase_tests.mk_dummy('ec06e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] MBM2', 'online');
select supabase_tests.mk_dummy('ec06e000-0000-4000-8000-0000000000a3'::uuid, '[TEST] MBM3', 'online');
select supabase_tests.mk_dummy('ec06e000-0000-4000-8000-0000000000f1'::uuid, '[TEST] MBF1', 'online');

update public.profiles set gender='female' where id='ec06e000-0000-4000-8000-0000000000f1';

-- Dana: m1 topup 500 · m2 topup 25 (konek oke, menit tak sanggup) ·
-- m3 topup 5 (konek pun tak sanggup).
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values
 ('ec06e000-0000-4000-8000-0000000000a1','topup','topup',500,'test-mb'),
 ('ec06e000-0000-4000-8000-0000000000a2','topup','topup',25,'test-mb'),
 ('ec06e000-0000-4000-8000-0000000000a3','topup','topup',5,'test-mb');

create temp table _mb (k text primary key, v text) on commit drop;
grant all on _mb to service_role;

-- Flag call_billing harus published (live bisa false) agar tick tidak free-pass.
update public.app_settings
   set feature_flags = feature_flags || '{"call_billing":{"published":true}}'::jsonb
 where id = 'global';

-- ════ 1. Grace <30 detik → gratis total, tak ada consumption ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at,
                          media_connected_at)
values ('ec06e000-0000-4000-8000-0000000000c1'::uuid,
        'ec06e000-0000-4000-8000-0000000000a1',
        'ec06e000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered', now() - interval '20 seconds',
        now() - interval '20 seconds');
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a1', true);
insert into _mb values ('g1',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('MB: <30s → can_continue, billed 0, charged 0',
  (select (v::jsonb->>'can_continue')::boolean from _mb where k='g1') = true
  and (select (v::jsonb->>'billed_minutes')::int from _mb where k='g1') = 0
  and (select (v::jsonb->>'charged_total')::int from _mb where k='g1') = 0
  and (select (v::jsonb->>'free_seconds_left')::int from _mb where k='g1') = 10,
  (select v from _mb where k='g1'));
select supabase_tests.check('MB: <30s → nol consumption & nol ledger debit',
  not exists (select 1 from public.yukcoin_consumptions
              where user_id='ec06e000-0000-4000-8000-0000000000a1'));

-- ════ 2. 45 detik (male caller) → konek 10 + menit 1 = 30; female +9 ════
update public.calls set answered_at = now() - interval '45 seconds', media_connected_at = now() - interval '45 seconds'
 where id='ec06e000-0000-4000-8000-0000000000c1';
insert into _mb values ('g2',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('MB: 45s → konek 10 + menit1 20 → charged 30',
  (select (v::jsonb->>'can_continue')::boolean from _mb where k='g2') = true
  and (select (v::jsonb->>'billed_minutes')::int from _mb where k='g2') = 1
  and (select (v::jsonb->>'charged_total')::int from _mb where k='g2') = 30,
  (select v from _mb where k='g2'));
select supabase_tests.check('MB: female +3 match_call_income (30% konek)',
  exists (select 1 from public.coin_ledger
          where user_id='ec06e000-0000-4000-8000-0000000000f1'
            and bucket='earned' and type='match_call_income' and amount=3));
select supabase_tests.check('MB: female +6 match_call_income (30% menit)',
  exists (select 1 from public.coin_ledger
          where user_id='ec06e000-0000-4000-8000-0000000000f1'
            and bucket='earned' and type='match_call_income' and amount=6));
select supabase_tests.check('MB: menit match TIDAK tertulis call_video_income',
  not exists (select 1 from public.coin_ledger
          where user_id='ec06e000-0000-4000-8000-0000000000f1'
            and type='call_video_income'
            and ref_id='ec06e000-0000-4000-8000-0000000000c1'));

-- ════ 3. Idempotent — tick ulang di 45s → tetap 30, konek tak dobel ════
insert into _mb values ('g3',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('MB: tick ulang → masih charged 30 (idempotent)',
  (select (v::jsonb->>'charged_total')::int from _mb where k='g3') = 30
  and (select (v::jsonb->>'billed_minutes')::int from _mb where k='g3') = 1,
  (select v from _mb where k='g3'));

-- ════ 4. 95 detik → menit ke-2 ikut → total 50, female total +15 ════
update public.calls set answered_at = now() - interval '95 seconds', media_connected_at = now() - interval '95 seconds'
 where id='ec06e000-0000-4000-8000-0000000000c1';
insert into _mb values ('g4',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('MB: 95s → billed 2 menit, charged 50',
  (select (v::jsonb->>'billed_minutes')::int from _mb where k='g4') = 2
  and (select (v::jsonb->>'charged_total')::int from _mb where k='g4') = 50,
  (select v from _mb where k='g4'));
select supabase_tests.check('MB: female total income 15 (3 konek + 2×6 menit)',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec06e000-0000-4000-8000-0000000000f1'
      and type = 'match_call_income') = 15);

-- ════ 5. FEMALE caller (random) → billing tetap di MALE (asimetri fix) ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at,
                          media_connected_at)
values ('ec06e000-0000-4000-8000-0000000000c2'::uuid,
        'ec06e000-0000-4000-8000-0000000000f1',
        'ec06e000-0000-4000-8000-0000000000a1',
        'random', 'video', 'answered', now() - interval '45 seconds',
        now() - interval '45 seconds');
-- Tick datang dari device FEMALE (caller) — sejak lockdown A2c recipient
-- READ-ONLY: tidak lagi memicu tagihan ke male (menutup celah "female terus
-- tick call lama → koin male terkuras").
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000f1', true);
insert into _mb values ('f1',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c2')::text);
select supabase_tests.check('MB: female-caller tick → read-only, can_continue',
  (select (v::jsonb->>'can_continue')::boolean from _mb where k='f1') = true
  and (select (v::jsonb->>'billed_minutes')::int from _mb where k='f1') = 0
  and (select (v::jsonb->>'charged_total')::int from _mb where k='f1') = 0,
  (select v from _mb where k='f1'));
select supabase_tests.check('MB: tick recipient TIDAK menagih male',
  (select coalesce(sum(-amount),0) from public.coin_ledger
    where user_id='ec06e000-0000-4000-8000-0000000000a1'
      and amount < 0
      and ref_id='ec06e000-0000-4000-8000-0000000000c2') = 0);

-- Tick dari device MALE (payer) — baru di sini tagihan jatuh: 10 + 20 = 30.
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a1', true);
insert into _mb values ('fc_m',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c2')::text);
select supabase_tests.check('MB: male tick → MALE tertagih 30',
  (select coalesce(sum(-amount),0) from public.coin_ledger
    where user_id='ec06e000-0000-4000-8000-0000000000a1'
      and amount < 0
      and ref_id='ec06e000-0000-4000-8000-0000000000c2') = 30);
select supabase_tests.check('MB: female TIDAK kena cabang free-limit (income +9)',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id='ec06e000-0000-4000-8000-0000000000f1'
      and type = 'match_call_income'
      and ref_id='ec06e000-0000-4000-8000-0000000000c2') = 9);

-- ════ 6. Male paid 25 → konek 10 lunas, menit gagal → pause + female +3 ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at,
                          media_connected_at)
values ('ec06e000-0000-4000-8000-0000000000c3'::uuid,
        'ec06e000-0000-4000-8000-0000000000a2',
        'ec06e000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered', now() - interval '45 seconds',
        now() - interval '45 seconds');
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a2', true);
insert into _mb values ('p1',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c3')::text);
select supabase_tests.check('MB: paid 25 → konek lunas, lalu insufficient',
  (select (v::jsonb->>'can_continue')::boolean from _mb where k='p1') = false
  and (select v::jsonb->>'reason' from _mb where k='p1') = 'insufficient'
  and (select (v::jsonb->>'charged_total')::int from _mb where k='p1') = 10,
  (select v from _mb where k='p1'));
select supabase_tests.check('MB: walau pause, female tetap +3 konek',
  exists (select 1 from public.coin_ledger
          where user_id='ec06e000-0000-4000-8000-0000000000f1'
            and type='match_call_income' and amount=3
            and ref_id='ec06e000-0000-4000-8000-0000000000c3'));

-- ════ 7. Male paid 5 → konek pun tak sanggup → pause, nol charge ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at,
                          media_connected_at)
values ('ec06e000-0000-4000-8000-0000000000c4'::uuid,
        'ec06e000-0000-4000-8000-0000000000a3',
        'ec06e000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered', now() - interval '45 seconds',
        now() - interval '45 seconds');
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a3', true);
insert into _mb values ('p2',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c4')::text);
select supabase_tests.check('MB: paid 5 → insufficient, nol consumption & nol income',
  (select (v::jsonb->>'can_continue')::boolean from _mb where k='p2') = false
  and (select (v::jsonb->>'charged_total')::int from _mb where k='p2') = 0
  and not exists (select 1 from public.yukcoin_consumptions
                  where ref_id='ec06e000-0000-4000-8000-0000000000c4'),
  (select v from _mb where k='p2'));

-- ════ 8. Tick dari NON-participant (random) → ditolak ════
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a1', true);
do $$ begin
  begin
    perform public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c4');
    insert into _mb values ('x1','no-throw');
  exception when others then
    insert into _mb values ('x1', sqlerrm);
  end;
end $$;
select supabase_tests.check('MB: tick non-participant random → "Only participants"',
  (select v from _mb where k='x1') = 'Only participants',
  (select v from _mb where k='x1'));

-- ════ 9. media_connected_at = jangkar grace (20261104000000) ════
-- Pair 45 detik lalu tapi media baru tersambung 5 detik → elapsed dihitung
-- dari media_connected_at → masih gratis (free_seconds_left ≈ 25).
insert into public.calls (id, caller_id, callee_id, kind, call_type, status,
                          answered_at, media_connected_at)
values ('ec06e000-0000-4000-8000-0000000000c5'::uuid,
        'ec06e000-0000-4000-8000-0000000000a1',
        'ec06e000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered',
        now() - interval '45 seconds', now() - interval '5 seconds');
insert into _mb values ('m1',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c5')::text);
select supabase_tests.check('MB: pair 45s + media 5s → gratis (free ≈ 25s)',
  (select (v::jsonb->>'can_continue')::boolean from _mb where k='m1') = true
  and (select (v::jsonb->>'billed_minutes')::int from _mb where k='m1') = 0
  and (select (v::jsonb->>'charged_total')::int from _mb where k='m1') = 0
  and (select (v::jsonb->>'free_seconds_left')::int from _mb where k='m1')
        between 24 and 26,
  (select v from _mb where k='m1'));

-- Media sudah 40 detik → konek 10 + menit 1 = 30 (elapsed dari connect).
update public.calls set media_connected_at = now() - interval '40 seconds'
 where id='ec06e000-0000-4000-8000-0000000000c5';
insert into _mb values ('m2',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c5')::text);
select supabase_tests.check('MB: media 40s → konek+menit charged 30',
  (select (v::jsonb->>'billed_minutes')::int from _mb where k='m2') = 1
  and (select (v::jsonb->>'charged_total')::int from _mb where k='m2') = 30,
  (select v from _mb where k='m2'));

-- 2026-11-09: TANPA media_connected_at (video tak pernah tersambung) →
-- TIDAK ditagih (dulu fallback ke answered_at → biaya konek tanpa video).
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ec06e000-0000-4000-8000-0000000000c6'::uuid,
        'ec06e000-0000-4000-8000-0000000000a1',
        'ec06e000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered', now() - interval '45 seconds');
insert into _mb values ('m3',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c6')::text);
select supabase_tests.check('MB: tanpa stamp media → tidak ditagih (charged 0)',
  coalesce((select (v::jsonb->>'charged_total')::int from _mb where k='m3'), 0) = 0,
  (select v from _mb where k='m3'));

-- ════ 10. touch_call(p_connected) → stamp sekali, earliest menang ════
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a1', true);
select public.touch_call('ec06e000-0000-4000-8000-0000000000c6', true);
select supabase_tests.check('MB: touch_call(connected) → stamp media_connected_at',
  (select media_connected_at is not null from public.calls
   where id='ec06e000-0000-4000-8000-0000000000c6'));
-- Stamp kedua (pihak lain, lebih lambat) tidak menimpa yang pertama.
update public.calls
   set media_connected_at = now() - interval '10 seconds'
 where id='ec06e000-0000-4000-8000-0000000000c6';
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000f1', true);
select public.touch_call('ec06e000-0000-4000-8000-0000000000c6', true);
select supabase_tests.check('MB: stamp kedua → earliest dipertahankan',
  (select media_connected_at < now() - interval '5 seconds' from public.calls
   where id='ec06e000-0000-4000-8000-0000000000c6'));

-- ════ 11. Tick sisi PENERIMA: jalur sama (idempotent) + income_total ════
-- 20261105000000: callee boleh tick — billing tetap diarahkan ke payer
-- (tak dobel karena idempotent), dan respons memuat income_total milik
-- callee untuk tampilan pendapatan live di UI-nya.
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000f1', true);
insert into _mb values ('r1',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('MB: callee tick → income_total=15 (3+2×6)',
  (select (v::jsonb->>'income_total')::int from _mb where k='r1') = 15,
  (select v from _mb where k='r1'));
select supabase_tests.check('MB: callee tick → consumption payer tak bertambah',
  (select count(*) from public.yukcoin_consumptions
    where ref_id = 'ec06e000-0000-4000-8000-0000000000c1') = 3,
  (select count(*)::text from public.yukcoin_consumptions
    where ref_id = 'ec06e000-0000-4000-8000-0000000000c1'));

-- Private call (kind bukan 'random'): callee juga boleh tick info-only.
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ec06e000-0000-4000-8000-0000000000c7'::uuid,
        'ec06e000-0000-4000-8000-0000000000a1',
        'ec06e000-0000-4000-8000-0000000000f1',
        'direct', 'video', 'answered', now() - interval '65 seconds');
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000a1', true);
insert into _mb values ('pv1',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c7')::text);
select set_config('request.jwt.claim.sub',
                  'ec06e000-0000-4000-8000-0000000000f1', true);
insert into _mb values ('r2',
  public.call_billing_tick('ec06e000-0000-4000-8000-0000000000c7')::text);
select supabase_tests.check('MB: private callee tick → income = ledger sum',
  (select (v::jsonb->>'income_total')::int from _mb where k='r2') =
    (select coalesce(sum(amount),0) from public.coin_ledger
      where user_id='ec06e000-0000-4000-8000-0000000000f1'
        and ref_id='ec06e000-0000-4000-8000-0000000000c7'
        and type like '%\_income'),
  (select v from _mb where k='r2'));
select supabase_tests.check('MB: private callee tick → income > 0 (billing sudah jalan)',
  (select (v::jsonb->>'income_total')::int from _mb where k='r2') > 0,
  (select v from _mb where k='r2'));
select supabase_tests.check('MB: private callee tick → tidak ditolak "Only caller"',
  (select v from _mb where k='r2') like '%"ok":true%' or
  (select v from _mb where k='r2') like '%"ok": true%',
  (select v from _mb where k='r2'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
