-- Lapis 3: matriks ekonomi — points_enabled ON/OFF × gender × auth.
-- Semantik baku (110013+): free-pass = aksi jalan tanpa tagih;
-- block = error; no-credit = reward tidak masuk; progress tetap jalan.
-- Jalankan: scripts/run_sql_tests.sh economy_matrix_test.sql
-- Transaksional — flag dikembalikan rollback. Hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ec02e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] MatM1', 'online');
select supabase_tests.mk_dummy('ec02e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] MatM2', 'online');
select supabase_tests.mk_dummy('ec02e000-0000-4000-8000-0000000000a3'::uuid, '[TEST] MatF1', 'online');

update public.profiles set gender = 'female',
       created_at = now() - interval '10 days'
 where id = 'ec02e000-0000-4000-8000-0000000000a3';
update public.profiles set subscription_price = 100
 where id = 'ec02e000-0000-4000-8000-0000000000a3';

-- Chat m1↔f1 untuk gift/coins; foto milik f1 untuk unlock.
insert into public.private_chats (chat_id, participants) values
 ('[TEST]-mx-a1a3', array['ec02e000-0000-4000-8000-0000000000a1',
                          'ec02e000-0000-4000-8000-0000000000a3']::uuid[]);
insert into public.user_photos (id, user_id, photo) values
 ('ec02e000-0000-4000-8000-0000000000f1',
  'ec02e000-0000-4000-8000-0000000000a3', '[TEST] photo');

-- Dana dummy: m1 paid+bonus (campur), m2 nol, f1 earned.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values
 ('ec02e000-0000-4000-8000-0000000000a1','topup','topup',100,'test-mx'),
 ('ec02e000-0000-4000-8000-0000000000a1','bonus','admin_mass_bonus',50,'test-mx'),
 ('ec02e000-0000-4000-8000-0000000000a1','earned','gift_recv',50,'test-mx'),
 ('ec02e000-0000-4000-8000-0000000000a3','earned','call_video_income',2000,'test-mx');

-- Flag fitur random_call published untuk uji join.
update public.app_settings
   set feature_flags = feature_flags || '{"random_call":{"published":true}}'::jsonb
 where id = 'global';

create temp table _mx (k text primary key, v text) on commit drop;
grant all on _mx to service_role;

-- ============================================================
-- FASE A: points_enabled = FALSE
-- ============================================================
update public.app_settings set points_enabled = false where id = 'global';

-- A1. spend_yukcoin → free-pass
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a1', true);
insert into _mx values ('spend_off',
  public.spend_yukcoin('ec02e000-0000-4000-8000-0000000000a1',
                       'match_search', 2, 'mx')::text);
select supabase_tests.check('OFF: spend_yukcoin → free, charged 0',
  (select v::jsonb->>'free' from _mx where k = 'spend_off') = 'true'
  and (select (v::jsonb->>'charged')::int from _mx where k = 'spend_off') = 0);
select supabase_tests.check('OFF: spend_yukcoin tidak menulis ledger',
  not exists (select 1 from public.coin_ledger
              where user_id = 'ec02e000-0000-4000-8000-0000000000a1'
                and type = 'match_search'));

-- A2. charge_metered → free-pass
insert into _mx values ('metered_off',
  public.charge_metered('ec02e000-0000-4000-8000-0000000000a1',
                        'call_video', 'mx', 1,
                        'ec02e000-0000-4000-8000-0000000000a3')::text);
select supabase_tests.check('OFF: charge_metered → charged 0',
  (select (v::jsonb->>'charged')::int from _mx where k = 'metered_off') = 0);

-- A3. deduct_chat_point('image') → gratis, tanpa ledger
insert into _mx values ('deduct_off',
  public.deduct_chat_point('image')::text);
select supabase_tests.check('OFF: deduct_chat_point tidak menagih',
  not exists (select 1 from public.coin_ledger
              where user_id = 'ec02e000-0000-4000-8000-0000000000a1'
                and type = 'spend_chat'));

-- A4. send_gift → block (exception)
do $$
begin
  perform public.send_gift('[TEST]-mx-a1a3',
    'ec02e000-0000-4000-8000-0000000000a3', 'rose');
  insert into _mx values ('gift_off', 'lolos');
exception when others then
  insert into _mx values ('gift_off', sqlerrm);
end $$;
select supabase_tests.check('OFF: send_gift → Points system disabled',
  (select v from _mx where k = 'gift_off') like '%Points system disabled%',
  (select v from _mx where k = 'gift_off'));

-- A5. send_coins → block
do $$
begin
  perform public.send_coins('[TEST]-mx-a1a3',
    'ec02e000-0000-4000-8000-0000000000a3', 10);
  insert into _mx values ('coins_off', 'lolos');
exception when others then
  insert into _mx values ('coins_off', sqlerrm);
end $$;
select supabase_tests.check('OFF: send_coins → Points system disabled',
  (select v from _mx where k = 'coins_off') like '%Points system disabled%',
  (select v from _mx where k = 'coins_off'));

-- A6. subscribe_creator → block
do $$
begin
  perform public.subscribe_creator(
    'ec02e000-0000-4000-8000-0000000000a3', 1);
  insert into _mx values ('sub_off', 'lolos');
exception when others then
  insert into _mx values ('sub_off', sqlerrm);
end $$;
select supabase_tests.check('OFF: subscribe_creator → Points system disabled',
  (select v from _mx where k = 'sub_off') like '%Points system disabled%',
  (select v from _mx where k = 'sub_off'));

-- A7. request_withdraw (female) → POINTS_DISABLED
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a3', true);
insert into _mx values ('wd_off',
  public.request_withdraw(1500, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('OFF: request_withdraw → POINTS_DISABLED',
  (select v::jsonb->>'error' from _mx where k = 'wd_off') = 'POINTS_DISABLED');

-- A8. claim_mission_reward → POINTS_DISABLED
insert into _mx values ('claim_off',
  public.claim_mission_reward('ec02e000-0000-4000-8000-0000000000a3',
                              'call_minutes')::text);
select supabase_tests.check('OFF: claim_mission_reward → POINTS_DISABLED',
  (select v::jsonb->>'error' from _mx where k = 'claim_off') = 'POINTS_DISABLED');

-- A9. credit_welcome_bonus → no-credit graceful
-- 2026-11-01: RPC ini service_role-only (client tidak boleh memanggil).
-- Uji melalui jalur resmi: set role service_role seperti edge function.
set local role service_role;
insert into _mx values ('wb_off',
  public.credit_welcome_bonus('ec02e000-0000-4000-8000-0000000000a2',
                              'test-inst-off1', 'register', '10.0.0.1')::text);
reset role;
select supabase_tests.check('OFF: welcome bonus → granted false, reason points_disabled',
  (select v::jsonb->>'granted' from _mx where k = 'wb_off') = 'false'
  and (select v::jsonb->>'reason' from _mx where k = 'wb_off') = 'points_disabled');
select supabase_tests.check('OFF: welcome bonus tidak menulis ledger',
  not exists (select 1 from public.coin_ledger
              where user_id = 'ec02e000-0000-4000-8000-0000000000a2'));

-- A10. update_mission_progress → TETAP JALAN (progress ≠ ekonomi)
insert into _mx values ('prog_off',
  public.update_mission_progress('ec02e000-0000-4000-8000-0000000000a3',
                                 'call_minutes', 5)::text);
select supabase_tests.check('OFF: update_mission_progress tetap jalan',
  (select (v::jsonb->>'progress')::int from _mx where k = 'prog_off') = 5);

-- A11. gate_feature → free selalu
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a1', true);
insert into _mx values ('gate_off',
  public.gate_feature('gender_filter', 'filter_gender')::text);
select supabase_tests.check('OFF: gate_feature → free:true charged:0',
  (select v::jsonb->>'free' from _mx where k = 'gate_off') = 'true'
  and (select (v::jsonb->>'charged')::int from _mx where k = 'gate_off') = 0);

-- A12. random_match_join: male saldo 0 tetap antre saat OFF (free)
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a2', true);
insert into _mx values ('join_off',
  public.random_match_join('all')::text);
select supabase_tests.check('OFF: male saldo 0 join → bukan no_funds',
  (select v::jsonb->>'status' from _mx where k = 'join_off') <> 'no_funds');
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a3', true);
insert into _mx values ('join_f_off',
  public.random_match_join('all')::text);
select supabase_tests.check('OFF: match terbentuk tanpa debit',
  (select v::jsonb->>'status' from _mx where k = 'join_f_off') = 'matched'
  and not exists (select 1 from public.coin_ledger
                  where type = 'match_search'
                    and user_id in ('ec02e000-0000-4000-8000-0000000000a1',
                                    'ec02e000-0000-4000-8000-0000000000a2',
                                    'ec02e000-0000-4000-8000-0000000000a3')));

-- A13. unlock_photo — FITUR DINONAKTIFKAN 2026-11-01 (EXECUTE dicabut).
-- Test lama dihapus; menyimpan test fungsi mati hanya menyesatkan.

-- ============================================================
-- FASE B: points_enabled = TRUE — gender & auth rules
-- ============================================================
update public.app_settings set points_enabled = true where id = 'global';
-- Bersihkan antrean fase A (pasangan f1↔m2 di A12 dibuat row pairs →
-- history-guard 10 menit menghalangi pair ulang; hapus agar deterministik).
delete from public.random_match_queue where user_id in
  ('ec02e000-0000-4000-8000-0000000000a1','ec02e000-0000-4000-8000-0000000000a2',
   'ec02e000-0000-4000-8000-0000000000a3');
delete from public.random_match_pairs where a in
  ('ec02e000-0000-4000-8000-0000000000a1','ec02e000-0000-4000-8000-0000000000a2',
   'ec02e000-0000-4000-8000-0000000000a3') or b in
  ('ec02e000-0000-4000-8000-0000000000a1','ec02e000-0000-4000-8000-0000000000a2',
   'ec02e000-0000-4000-8000-0000000000a3');
delete from public.calls where caller_id in
  ('ec02e000-0000-4000-8000-0000000000a1','ec02e000-0000-4000-8000-0000000000a2',
   'ec02e000-0000-4000-8000-0000000000a3') or callee_id in
  ('ec02e000-0000-4000-8000-0000000000a1','ec02e000-0000-4000-8000-0000000000a2',
   'ec02e000-0000-4000-8000-0000000000a3');

-- B1. male m1 bayar match fee (earned/bonus), revenue tercatat
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a1', true);
insert into _mx values ('spend_on',
  public.spend_yukcoin('ec02e000-0000-4000-8000-0000000000a1',
                       'match_search', 2, 'mx')::text);
select supabase_tests.check('ON: spend_yukcoin male → charged 2',
  (select (v::jsonb->>'charged')::int from _mx where k = 'spend_on') = 2);
select supabase_tests.check('ON: match fee → platform_revenue',
  exists (select 1 from public.platform_revenue
          where source = 'match_search'
            and from_user = 'ec02e000-0000-4000-8000-0000000000a1'));

-- B2. female selalu free untuk match_search
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a3', true);
insert into _mx values ('spend_f',
  public.spend_yukcoin('ec02e000-0000-4000-8000-0000000000a3',
                       'match_search', 2, 'mx')::text);
select supabase_tests.check('ON: spend_yukcoin female → free charged 0',
  (select v::jsonb->>'free' from _mx where k = 'spend_f') = 'true'
  and (select (v::jsonb->>'charged')::int from _mx where k = 'spend_f') = 0);

-- B3. cross-uid spend → Forbidden (exception 42501)
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a1', true);
do $$
begin
  perform public.spend_yukcoin('ec02e000-0000-4000-8000-0000000000a3',
                               'match_search', 2, 'mx');
  insert into _mx values ('spend_cross', 'lolos');
exception when others then
  insert into _mx values ('spend_cross', sqlerrm);
end $$;
select supabase_tests.check('ON: spend uid lain → Forbidden',
  (select v from _mx where k = 'spend_cross') like '%Forbidden%',
  (select v from _mx where k = 'spend_cross'));

-- B4. mission cross-uid → FORBIDDEN (jsonb error)
insert into _mx values ('prog_cross',
  public.update_mission_progress('ec02e000-0000-4000-8000-0000000000a3',
                                 'call_minutes', 1)::text);
select supabase_tests.check('ON: update_mission_progress uid lain → FORBIDDEN',
  (select v::jsonb->>'error' from _mx where k = 'prog_cross') = 'FORBIDDEN');
insert into _mx values ('claim_cross',
  public.claim_mission_reward('ec02e000-0000-4000-8000-0000000000a3',
                              'call_minutes')::text);
select supabase_tests.check('ON: claim_mission_reward uid lain → FORBIDDEN',
  (select v::jsonb->>'error' from _mx where k = 'claim_cross') = 'FORBIDDEN');

-- B5. _spend_yukcoin_core tidak bisa dipanggil user
select supabase_tests.check('_spend_yukcoin_core revoked dari authenticated',
  not has_function_privilege('authenticated',
    'public._spend_yukcoin_core(uuid,text,integer,text,jsonb)', 'EXECUTE'));
select supabase_tests.check('_spend_yukcoin_core revoked dari anon',
  not has_function_privilege('anon',
    'public._spend_yukcoin_core(uuid,text,integer,text,jsonb)', 'EXECUTE'));

-- B6. request_withdraw male → FEMALE_ONLY; female di bawah min → BELOW_MINIMUM
insert into _mx values ('wd_male',
  public.request_withdraw(2000, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('ON: withdraw male → FEMALE_ONLY',
  (select v::jsonb->>'error' from _mx where k = 'wd_male') = 'FEMALE_ONLY');
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a3', true);
insert into _mx values ('wd_min',
  public.request_withdraw(100, '081234567890', '[TEST] Dana')::text);
select supabase_tests.check('ON: withdraw < min → BELOW_MINIMUM',
  (select v::jsonb->>'error' from _mx where k = 'wd_min') = 'BELOW_MINIMUM');

-- B7. male saldo 0 spend → raise 'YukCoin tidak cukup'
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a2', true);
do $$
begin
  perform public.spend_yukcoin('ec02e000-0000-4000-8000-0000000000a2',
                               'match_search', 2, 'mx');
  insert into _mx values ('spend_broke', 'lolos');
exception when others then
  insert into _mx values ('spend_broke', sqlerrm);
end $$;
select supabase_tests.check('ON: male saldo 0 → YukCoin tidak cukup',
  (select v from _mx where k = 'spend_broke') like '%YukCoin tidak cukup%',
  (select v from _mx where k = 'spend_broke'));

-- B8. welcome bonus female → female_no_bonus; male → granted
select set_config('request.jwt.claim.sub', 'ec02e000-0000-4000-8000-0000000000a3', true);
set local role service_role;
insert into _mx values ('wb_f',
  public.credit_welcome_bonus('ec02e000-0000-4000-8000-0000000000a3',
                              'test-inst-f01', 'register', '10.0.0.2')::text);
reset role;
select supabase_tests.check('ON: welcome female → female_no_bonus',
  (select v::jsonb->>'granted' from _mx where k = 'wb_f') = 'false'
  and (select v::jsonb->>'reason' from _mx where k = 'wb_f') = 'female_no_bonus');
set local role service_role;
insert into _mx values ('wb_m',
  public.credit_welcome_bonus('ec02e000-0000-4000-8000-0000000000a2',
                              'test-inst-m01', 'register', '10.0.0.3')::text);
reset role;
select supabase_tests.check('ON: welcome male → granted, ledger welcome_register',
  (select v::jsonb->>'granted' from _mx where k = 'wb_m') = 'true'
  and exists (select 1 from public.coin_ledger
              where user_id = 'ec02e000-0000-4000-8000-0000000000a2'
                and bucket = 'bonus' and type = 'welcome_register'));

-- B9. misi complete + klaim → kredit earned 'mission_reward'; re-claim ditolak
insert into _mx values ('prog_f',
  public.update_mission_progress('ec02e000-0000-4000-8000-0000000000a3',
                                 'call_minutes', 30)::text);
select supabase_tests.check('ON: misi 30/30 → completed',
  (select v::jsonb->>'completed' from _mx where k = 'prog_f') = 'true');
insert into _mx values ('claim_f',
  public.claim_mission_reward('ec02e000-0000-4000-8000-0000000000a3',
                              'call_minutes')::text);
select supabase_tests.check('ON: claim misi → success, earned +reward',
  (select v::jsonb->>'success' from _mx where k = 'claim_f') = 'true'
  and exists (select 1 from public.coin_ledger
              where user_id = 'ec02e000-0000-4000-8000-0000000000a3'
                and bucket = 'earned' and type = 'mission_reward'
                and ref_id = 'call_minutes'));
insert into _mx values ('claim2',
  public.claim_mission_reward('ec02e000-0000-4000-8000-0000000000a3',
                              'call_minutes')::text);
select supabase_tests.check('ON: re-claim → ALREADY_CLAIMED',
  (select v::jsonb->>'error' from _mx where k = 'claim2') = 'ALREADY_CLAIMED');

-- B10. tanpa auth → Not authenticated
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.send_coins('[TEST]-mx-a1a3',
    'ec02e000-0000-4000-8000-0000000000a3', 10);
  insert into _mx values ('noauth', 'lolos');
exception when others then
  insert into _mx values ('noauth', sqlerrm);
end $$;
select supabase_tests.check('ON: tanpa auth → Not authenticated',
  (select v from _mx where k = 'noauth') like '%Not authenticated%',
  (select v from _mx where k = 'noauth'));

select supabase_tests.report() as result;
rollback;
