-- Lapis 4: Economy leak lockdown (20261106000000) — Fase A.
--   A1: _charge_metered_core/touch_call/yukcoin_paid_total tak lagi bisa
--       dieksekusi peran client (anon/authenticated).
--   A2: call_billing_tick cap elapsed ke ended_at + recipient read-only.
--   A3: guard calls — klien tak bisa ubah kind/answered_at/media_connected_at
--       & tak bisa insert call non-direct.
--   A4: unique menit di yukcoin_consumptions; bucket tak boleh negatif.
--   A5: economy_invariant_cron ada & bisa jalan.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed060000-0000-4000-8000-0000000000a1'::uuid, '[TEST] LKM1', 'online');
select supabase_tests.mk_dummy('ed060000-0000-4000-8000-0000000000f1'::uuid, '[TEST] LKF1', 'online');
update public.profiles set gender='female' where id='ed060000-0000-4000-8000-0000000000f1';

insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed060000-0000-4000-8000-0000000000a1','topup','topup',500,'test-lk');

create temp table _lk (k text primary key, v text) on commit drop;
grant all on _lk to service_role;

update public.app_settings
   set feature_flags = feature_flags || '{"call_billing":{"published":true}}'::jsonb
 where id = 'global';

-- ════ A1. Privilege internal dipagari grant ════
select supabase_tests.check('LK: _charge_metered_core tidak executable anon',
  has_function_privilege('anon',
    'public._charge_metered_core(uuid,text,text,integer,uuid,text)', 'execute') = false);
select supabase_tests.check('LK: _charge_metered_core tidak executable authenticated',
  has_function_privilege('authenticated',
    'public._charge_metered_core(uuid,text,text,integer,uuid,text)', 'execute') = false);
select supabase_tests.check('LK: touch_call tidak executable anon',
  has_function_privilege('anon', 'public.touch_call(uuid,boolean)', 'execute') = false);
select supabase_tests.check('LK: yukcoin_paid_total tidak executable authenticated',
  has_function_privilege('authenticated',
    'public.yukcoin_paid_total(uuid)', 'execute') = false);
-- Pemakaian internal lewat definer tetap sah (service role mengeksekusi apa pun).
select supabase_tests.check('LK: call_billing_tick tetap executable authenticated',
  has_function_privilege('authenticated',
    'public.call_billing_tick(uuid)', 'execute') = true);

-- ════ A2a. Tick setelah ended → cap di ended_at, can_continue=false ════
-- Call direct berakhir di menit ke-2 (answered 130 dtk lalu, ended 30 dtk lalu
-- → durasi aktual 100 dtk = 2 menit tagih, bukan 3).
insert into public.calls (id, caller_id, callee_id, kind, call_type, status,
                          answered_at, ended_at)
values ('ed060000-0000-4000-8000-0000000000c1'::uuid,
        'ed060000-0000-4000-8000-0000000000a1',
        'ed060000-0000-4000-8000-0000000000f1',
        'direct', 'video', 'ended',
        now() - interval '130 seconds', now() - interval '30 seconds');
select set_config('request.jwt.claim.sub',
                  'ed060000-0000-4000-8000-0000000000a1', true);
insert into _lk values ('e1',
  public.call_billing_tick('ed060000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('LK: ended call → can_continue=false + ended flag',
  (select (v::jsonb->>'can_continue')::boolean from _lk where k='e1') = false
  and (select (v::jsonb->>'ended')::boolean from _lk where k='e1') = true,
  (select v from _lk where k='e1'));
select supabase_tests.check('LK: ended call → billed 2 menit (cap ended_at), bukan 3',
  (select (v::jsonb->>'billed_minutes')::int from _lk where k='e1') = 2,
  (select v from _lk where k='e1'));
-- Tick ulang → tetap 2 (idempotent, tak mengejar now()).
insert into _lk values ('e2',
  public.call_billing_tick('ed060000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('LK: tick ulang pasca-ended → tetap 2 menit',
  (select (v::jsonb->>'billed_minutes')::int from _lk where k='e2') = 2,
  (select v from _lk where k='e2'));

-- ════ A2b. Recipient read-only: tak memicu charge baru ════
-- Call masih berjalan; payer miskin (akan kena 'insufficient' kalau ditagih).
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ed060000-0000-4000-8000-0000000000c2'::uuid,
        'ed060000-0000-4000-8000-0000000000a1',
        'ed060000-0000-4000-8000-0000000000f1',
        'random', 'video', 'answered', now() - interval '45 seconds');
select set_config('request.jwt.claim.sub',
                  'ed060000-0000-4000-8000-0000000000f1', true);
insert into _lk values ('r1',
  public.call_billing_tick('ed060000-0000-4000-8000-0000000000c2')::text);
select supabase_tests.check('LK: recipient tick → read-only (0 consumption)',
  not exists (select 1 from public.yukcoin_consumptions
              where ref_id = 'ed060000-0000-4000-8000-0000000000c2'),
  (select v from _lk where k='r1'));
select supabase_tests.check('LK: recipient tick → ok + role recipient',
  (select (v::jsonb->>'ok')::boolean from _lk where k='r1') = true
  and (select v::jsonb->>'role' from _lk where k='r1') = 'recipient',
  (select v from _lk where k='r1'));

-- ════ A3. Guard kolom billing di calls ════
-- Konteks client = role authenticated. `set local role` di DALAM do-block
-- (scope fungsi → auto-revert saat block keluar) supaya check() tetap jalan
-- sebagai service role.
create temp table _g (k text primary key, ok boolean, msg text) on commit drop;
grant all on _g to service_role;
grant all on _g to authenticated;

-- A3a. Insert call 'random' langsung oleh client → ditolak.
do $$
declare v_ok boolean; v_msg text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',
                     'ed060000-0000-4000-8000-0000000000a1', true);
  begin
    insert into public.calls (id, caller_id, callee_id, kind, call_type, status,
                              answered_at)
    values (gen_random_uuid(),
            'ed060000-0000-4000-8000-0000000000a1',
            'ed060000-0000-4000-8000-0000000000f1',
            'random', 'video', 'answered', now() - interval '1 hour');
    v_ok := false; v_msg := 'no exception';
  exception when others then
    v_ok := true; v_msg := sqlerrm;
  end;
  reset role;
  insert into _g values ('a3a', v_ok, v_msg);
end $$;
select supabase_tests.check('LK: client insert call random+answered → ditolak',
  (select ok from _g where k='a3a') = true,
  (select msg from _g where k='a3a'));

-- A3b. Update answered_at ke masa lalu (backdate) → ditolak.
do $$
declare v_ok boolean; v_msg text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',
                     'ed060000-0000-4000-8000-0000000000a1', true);
  begin
    update public.calls set answered_at = now() - interval '1 hour'
     where id = 'ed060000-0000-4000-8000-0000000000c2';
    v_ok := false; v_msg := 'no exception';
  exception when others then
    v_ok := true; v_msg := sqlerrm;
  end;
  reset role;
  insert into _g values ('a3b', v_ok, v_msg);
end $$;
select supabase_tests.check('LK: client backdate answered_at → ditolak',
  (select ok from _g where k='a3b') = true,
  (select msg from _g where k='a3b'));

-- A3c. Update media_connected_at oleh client → ditolak.
do $$
declare v_ok boolean; v_msg text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',
                     'ed060000-0000-4000-8000-0000000000a1', true);
  begin
    update public.calls set media_connected_at = now()
     where id = 'ed060000-0000-4000-8000-0000000000c2';
    v_ok := false; v_msg := 'no exception';
  exception when others then
    v_ok := true; v_msg := sqlerrm;
  end;
  reset role;
  insert into _g values ('a3c', v_ok, v_msg);
end $$;
select supabase_tests.check('LK: client tulis media_connected_at → ditolak',
  (select ok from _g where k='a3c') = true,
  (select msg from _g where k='a3c'));

-- A3d. Update kind → ditolak.
do $$
declare v_ok boolean; v_msg text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',
                     'ed060000-0000-4000-8000-0000000000a1', true);
  begin
    update public.calls set kind = 'random'
     where id = 'ed060000-0000-4000-8000-0000000000c1';
    v_ok := false; v_msg := 'no exception';
  exception when others then
    v_ok := true; v_msg := sqlerrm;
  end;
  reset role;
  insert into _g values ('a3d', v_ok, v_msg);
end $$;
select supabase_tests.check('LK: client ubah kind → ditolak',
  (select ok from _g where k='a3d') = true,
  (select msg from _g where k='a3d'));

-- A3e. Update status/ended_at SAH (alur hangup normal tetap jalan).
do $$
declare v_ok boolean := true; v_msg text := 'ok';
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',
                     'ed060000-0000-4000-8000-0000000000a1', true);
  begin
    update public.calls set status = 'ended', ended_at = now()
     where id = 'ed060000-0000-4000-8000-0000000000c2';
  exception when others then
    v_ok := false; v_msg := sqlerrm;
  end;
  reset role;
  insert into _g values ('a3e', v_ok, v_msg);
end $$;
select supabase_tests.check('LK: client update status+ended_at (hangup) → diizinkan',
  (select ok from _g where k='a3e') = true,
  (select msg from _g where k='a3e'));

-- ════ A4a. Unique index menit — insert menit sama dua kali gagal ════
delete from _g;
do $$
begin
  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
  values ('ed060000-0000-4000-8000-0000000000a1', 'call_video', 20,
          'uniq-test', '{"minute": 1}'),
         ('ed060000-0000-4000-8000-0000000000a1', 'call_video', 20,
          'uniq-test', '{"minute": 1}');
  insert into _g values ('u1', false, 'no exception');
exception when others then
  insert into _g values ('u1', true, sqlerrm);
end $$;
select supabase_tests.check('LK: consumption menit dobel → ditolak unique index',
  (select ok from _g where k='u1') = true,
  (select msg from _g where k='u1'));

-- ════ A4b. Bucket tak boleh negatif ════
delete from _g;
do $$
begin
  -- m1 topup 500; debit bonus 1 (bonus=0) → harus gagal oleh guard nonneg.
  insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
  values ('ed060000-0000-4000-8000-0000000000a1','bonus','test_debit',-1,'x');
  insert into _g values ('n1', false, 'no exception');
exception when others then
  insert into _g values ('n1', true, sqlerrm);
end $$;
select supabase_tests.check('LK: debit melebihi bucket → ditolak guard nonneg',
  (select ok from _g where k='n1') = true,
  (select msg from _g where k='n1'));

-- Debit SAH (topup punya 500) → lolos.
do $$
begin
  insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
  values ('ed060000-0000-4000-8000-0000000000a1','topup','test_debit',-5,'x');
  insert into _g values ('n2', true, 'ok');
exception when others then
  insert into _g values ('n2', false, sqlerrm);
end $$;
select supabase_tests.check('LK: debit sah (saldo cukup) → lolos',
  (select ok from _g where k='n2') = true,
  (select msg from _g where k='n2'));

-- ════ A5. Invariant cron ════
select supabase_tests.check('LK: cron economy-invariant-daily terjadwal',
  exists (select 1 from cron.job where jobname = 'economy-invariant-daily'));
select supabase_tests.check('LK: economy_invariant_cron jalan (return int ≥ 0)',
  public.economy_invariant_cron() >= 0);

-- ════ KYC grants (20261108000000) — klien butuh submit/get_my_kyc; ════
-- admin_* bisa dieksekusi authenticated (guard email di dalam fungsi).
select supabase_tests.check('LK: submit_kyc executable authenticated',
  has_function_privilege('authenticated',
    'public.submit_kyc(text,text,text,text,text,date)', 'execute') = true);
select supabase_tests.check('LK: get_my_kyc executable authenticated',
  has_function_privilege('authenticated',
    'public.get_my_kyc()', 'execute') = true);
select supabase_tests.check('LK: admin_kyc_list executable authenticated',
  has_function_privilege('authenticated',
    'public.admin_kyc_list(text)', 'execute') = true);
select supabase_tests.check('LK: admin_kyc_review executable authenticated',
  has_function_privilege('authenticated',
    'public.admin_kyc_review(uuid,boolean,text)', 'execute') = true);
select supabase_tests.check('LK: submit_kyc TIDAK executable anon',
  has_function_privilege('anon',
    'public.submit_kyc(text,text,text,text,text,date)', 'execute') = false);

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
