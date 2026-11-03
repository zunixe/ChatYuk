-- pgTAP: guard ekonomi hasil audit 2026-11-01 (Fase 21).
--
-- Mengunci 6 pertahanan baru supaya tidak bisa regresi diam-diam:
--   1. credit_welcome_bonus & charge_metered TIDAK bisa dipanggil client
--      (dulu = cetak koin gratis + cuci bonus jadi earned).
--   2. send_room_gift mati total (gift hanya 1:1).
--   3. user_missions & point_events tidak bisa ditulis client.
--   4. update_mission_progress meng-clamp increment raksasa.
--   5. profiles.points tidak bisa ditulis client.
--   6. withdraw: debit sekali saat request; reject me-refund penuh.
--
-- Transaksional (BEGIN/ROLLBACK) — tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

create temp table _gw (key text primary key, val text) on commit drop;
grant all on _gw to service_role;

-- ════ 1. RPC pencetak koin tidak bisa dipanggil client ════
select supabase_tests.check('credit_welcome_bonus hanya service_role',
  not has_function_privilege('authenticated',
    'public.credit_welcome_bonus(uuid,text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.credit_welcome_bonus(uuid,text,text,text)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.credit_welcome_bonus(uuid,text,text,text)', 'EXECUTE'));

select supabase_tests.check('charge_metered hanya service_role',
  not has_function_privilege('authenticated',
    'public.charge_metered(uuid,text,text,integer,uuid)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.charge_metered(uuid,text,text,integer,uuid)', 'EXECUTE'));

-- ════ 2. Gift room mati (gift hanya chat pribadi) ════
select supabase_tests.check('send_room_gift tidak bisa dipanggil siapa pun',
  not has_function_privilege('authenticated',
    'public.send_room_gift(text,text,integer)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.send_room_gift(text,text,integer)', 'EXECUTE'));

select supabase_tests.check('send_room_gift badan selalu menolak',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'send_room_gift'
      and pg_get_functiondef(p.oid) like '%Gift hanya untuk chat pribadi%'
  ));

-- ════ 3. Tabel misi & event tidak bisa ditulis client ════
select supabase_tests.check('user_missions: client hanya SELECT',
  not has_table_privilege('authenticated', 'public.user_missions', 'INSERT')
  and not has_table_privilege('authenticated', 'public.user_missions', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.user_missions', 'DELETE')
  and has_table_privilege('authenticated', 'public.user_missions', 'SELECT'));

select supabase_tests.check('point_events: client hanya SELECT',
  not has_table_privilege('authenticated', 'public.point_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.point_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.point_events', 'DELETE')
  and has_table_privilege('authenticated', 'public.point_events', 'SELECT'));

-- ════ 4. Clamp increment misi ════
select supabase_tests.mk_dummy('ec04e000-0000-4000-8000-0000000000b1'::uuid,
                               '[TEST] ClampM', 'online');
select set_config('request.jwt.claim.sub',
                  'ec04e000-0000-4000-8000-0000000000b1', true);

insert into _gw(key, val)
  select 'big_inc',
         (public.update_mission_progress(
            'ec04e000-0000-4000-8000-0000000000b1',
            'upload_photos', 1000000) ->> 'progress');

select supabase_tests.check('increment 1.000.000 di-clamp ke target (3)',
  (select val::int from _gw where key = 'big_inc') =
  (select target_value from public.missions where mission_key = 'upload_photos'));

-- ════ 5. profiles.points tidak bisa ditulis client ════
select supabase_tests.check('trigger guard_economy_columns terpasang',
  exists(select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
          where c.relname = 'profiles'
            and t.tgname = 'guard_economy_columns_trg'
            and not t.tgisinternal));

select supabase_tests.check('ledger_spend memakai advisory lock',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'ledger_spend'
      and pg_get_functiondef(p.oid) like '%pg_advisory_xact_lock%'
  ));

-- ════ 6. Withdraw: satu titik debit + refund saat reject ════
-- Seed dulu sebagai konteks internal (tanpa JWT): guard_economy_columns
-- mengunci `created_at` untuk permintaan client, jadi penuaan akun uji
-- harus dilakukan sebelum claim sub di-set.
select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.mk_dummy('ec04e000-0000-4000-8000-0000000000b2'::uuid,
                               '[TEST] WdRefund', 'online');
update public.profiles set gender = 'female', created_at = now() - interval '10 days'
 where id = 'ec04e000-0000-4000-8000-0000000000b2';
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id)
values ('ec04e000-0000-4000-8000-0000000000b2', 'earned', 'test_seed', 2000, 'gw-seed');

-- Fase B: withdraw wajib KYC approved.
insert into public.kyc_requests (user_id, status, full_name, id_number,
                                 id_photo, selfie_photo)
values ('ec04e000-0000-4000-8000-0000000000b2', 'approved',
        '[TEST] WdRefund', '3201xxxx', 'x', 'x');
select set_config('request.jwt.claim.sub',
                  'ec04e000-0000-4000-8000-0000000000b2', true);
insert into _gw(key, val)
  select 'wd_req', public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text;

select supabase_tests.check('withdraw: debit −2000 SAAT request',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id = 'ec04e000-0000-4000-8000-0000000000b2') = 0);

select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
insert into _gw(key, val)
  select 'wd_reject', public.admin_withdraw_process(
    (select id from public.withdrawal_requests
      where user_id = 'ec04e000-0000-4000-8000-0000000000b2'
        and status = 'pending' limit 1),
    false, '[TEST] reject')::text;
select set_config('request.jwt.claim.email', '', true);

select supabase_tests.check('withdraw reject → refund penuh (saldo 2000)',
  (select coalesce(sum(amount),0) from public.coin_ledger
    where user_id = 'ec04e000-0000-4000-8000-0000000000b2') = 2000);

select supabase_tests.check('withdraw reject → status rejected',
  exists(select 1 from public.withdrawal_requests
          where user_id = 'ec04e000-0000-4000-8000-0000000000b2'
            and status = 'rejected'));

-- Reject kedua pada baris yang sama → ditolak (bukan refund dobel).
select set_config('request.jwt.claim.email', 'zunixe@gmail.com', true);
insert into _gw(key, val) select 'wd_reject2',
  public.admin_withdraw_process(
    (select id from public.withdrawal_requests
      where user_id = 'ec04e000-0000-4000-8000-0000000000b2' limit 1),
    false, '[TEST] reject lagi')::text;
select set_config('request.jwt.claim.email', '', true);

select supabase_tests.check('reject kedua → ALREADY_PROCESSED, tanpa refund dobel',
  (select val::jsonb ->> 'error' from _gw where key = 'wd_reject2')
    = 'ALREADY_PROCESSED'
  and (select coalesce(sum(amount),0) from public.coin_ledger
        where user_id = 'ec04e000-0000-4000-8000-0000000000b2') = 2000);

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
