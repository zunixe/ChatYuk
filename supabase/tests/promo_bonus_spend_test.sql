-- Lapis 3: bonus male untuk call/gift/kirim koin/langganan (20261110050000).
--   P1: call 2 menit dari bonus → bonus −120 (×3), female earned +12.
--   P2: gift rose (10) dari bonus → bonus −30, female earned net 7.
--   P3: koin beli dipakai DULU (topup 10 + bonus untuk sisa).
--   P4: device dipakai akun lain → bonus tak berlaku.
--   P5: plafon habis → bonus tak berlaku; promo_idr tercatat.
--   P6: female/anon tidak bisa menambal dengan bonus.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed0e0000-0000-4000-8000-0000000000a1'::uuid, '[TEST] PB-M1', 'online');
select supabase_tests.mk_dummy('ed0e0000-0000-4000-8000-0000000000a2'::uuid, '[TEST] PB-M2', 'online');
select supabase_tests.mk_dummy('ed0e0000-0000-4000-8000-0000000000f1'::uuid, '[TEST] PB-F1', 'online');
update public.profiles set gender = 'male', is_registered = true,
       created_at = now() - interval '30 days'
 where id in ('ed0e0000-0000-4000-8000-0000000000a1', 'ed0e0000-0000-4000-8000-0000000000a2');
update public.profiles set gender = 'female', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'ed0e0000-0000-4000-8000-0000000000f1';
update public.app_settings
   set promo_budget_idr_monthly = 1000000000, bonus_price_multiplier = 3,
       call_cut_pct = 70, gift_cut_pct = 30, coin_send_cut_pct = 30,
       feature_flags = feature_flags || '{"call_billing":{"published":true}}'::jsonb
 where id = 'global';

insert into public.user_devices (user_id, install_id) values
  ('ed0e0000-0000-4000-8000-0000000000a1', 'drm-test-pb-m1'),
  ('ed0e0000-0000-4000-8000-0000000000f1', 'drm-test-pb-f1'),
  -- M2 berbagi device dengan akun lain (F1).
  ('ed0e0000-0000-4000-8000-0000000000a2', 'drm-test-pb-f1');
insert into public.private_chats (chat_id, participants) values
  ('[TEST]-pb-m1f1', array['ed0e0000-0000-4000-8000-0000000000a1','ed0e0000-0000-4000-8000-0000000000f1']::uuid[]),
  ('[TEST]-pb-m2f1', array['ed0e0000-0000-4000-8000-0000000000a2','ed0e0000-0000-4000-8000-0000000000f1']::uuid[]);
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
  ('ed0e0000-0000-4000-8000-0000000000a1', 'bonus', 'daily_login', 300, '[TEST]pb'),
  ('ed0e0000-0000-4000-8000-0000000000a2', 'bonus', 'daily_login', 300, '[TEST]pb'),
  ('ed0e0000-0000-4000-8000-0000000000f1', 'bonus', 'mission_reward', 300, '[TEST]pb');

create temp table _pb (k text primary key, v text) on commit drop;
grant all on _pb to service_role;

-- ════ P1. Call 2 menit dari bonus ════
insert into public.calls (id, caller_id, callee_id, kind, call_type, status, answered_at)
values ('ed0e0000-0000-4000-8000-0000000000c1'::uuid,
        'ed0e0000-0000-4000-8000-0000000000a1', 'ed0e0000-0000-4000-8000-0000000000f1',
        'direct', 'video', 'answered', now() - interval '70 seconds');
select set_config('request.jwt.claim.sub', 'ed0e0000-0000-4000-8000-0000000000a1', true);
insert into _pb values ('c1', public.call_billing_tick('ed0e0000-0000-4000-8000-0000000000c1')::text);
select supabase_tests.check('P1: call 2 menit dari bonus → tertagih 2 menit',
  (select (v::jsonb->>'billed_minutes')::int from _pb where k='c1') = 2,
  (select v from _pb where k='c1'));
select supabase_tests.check('P1: bonus male −120 (×3)',
  (select sum(amount) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000a1' and bucket = 'bonus') = 180);
select supabase_tests.check('P1: female earned +12 (30% dari 40)',
  (select coalesce(sum(amount), 0) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000f1' and bucket = 'earned') = 12);

-- ════ P2. Gift rose (10) dari bonus ════
insert into _pb values ('g1', public.send_gift('[TEST]-pb-m1f1',
  'ed0e0000-0000-4000-8000-0000000000f1', 'rose')::text);
select supabase_tests.check('P2: gift dari bonus → bonus −30, female +7',
  (select sum(amount) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000a1' and bucket = 'bonus') = 150
  and (select sum(amount) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000f1' and bucket = 'earned') = 19,
  (select v from _pb where k='g1'));

-- ════ P3. Koin beli dulu ════
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('ed0e0000-0000-4000-8000-0000000000a1', 'topup', 'topup', 10, '[TEST]pb-t');
insert into _pb values ('s1', public.send_coins('[TEST]-pb-m1f1',
  'ed0e0000-0000-4000-8000-0000000000f1', 20)::text);
select supabase_tests.check('P3: kirim 20 = topup 10 + bonus 30 (sisa 10 × 3)',
  (select sum(amount) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000a1' and bucket = 'topup') = 0
  and (select sum(amount) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000a1' and bucket = 'bonus') = 120,
  (select v from _pb where k='s1'));
select supabase_tests.check('P5: promo_idr tercatat (call 79.8 + gift 46.55 + kirim 46.55)',
  (select sum((metadata->>'promo_idr')::numeric) from public.coin_ledger
    where user_id = 'ed0e0000-0000-4000-8000-0000000000a1' and bucket = 'bonus'
      and amount < 0) = 172.90);
select set_config('request.jwt.claim.sub', 'ed0e0000-0000-4000-8000-0000000000a1', true);
select supabase_tests.check('get_wallet: promo_ok & multiplier',
  (public.get_wallet()->>'promo_ok')::boolean
  and (public.get_wallet()->>'bonus_multiplier')::int = 3);

-- ════ P4. Device dipakai akun lain ════
select set_config('request.jwt.claim.sub', 'ed0e0000-0000-4000-8000-0000000000a2', true);
do $$
declare v_msg text := 'no exception';
begin
  begin
    perform public.send_gift('[TEST]-pb-m2f1', 'ed0e0000-0000-4000-8000-0000000000f1', 'rose');
  exception when others then v_msg := sqlerrm; end;
  insert into _pb values ('g2', v_msg);
end $$;
select supabase_tests.check('P4: device berbagi → gift dari bonus ditolak',
  (select v from _pb where k='g2') <> 'no exception', (select v from _pb where k='g2'));

-- ════ P6. Female tidak bisa menambal dengan bonus ════
select set_config('request.jwt.claim.sub', 'ed0e0000-0000-4000-8000-0000000000f1', true);
do $$
declare v_msg text := 'no exception';
begin
  begin
    -- Saldo earned female 33 < 50 (teddy) → butuh bonus → harus ditolak.
    perform public.send_gift('[TEST]-pb-m1f1', 'ed0e0000-0000-4000-8000-0000000000a1', 'teddy');
  exception when others then v_msg := sqlerrm; end;
  insert into _pb values ('g3', v_msg);
end $$;
select supabase_tests.check('P6: female tak bisa pakai bonus',
  (select v from _pb where k='g3') <> 'no exception', (select v from _pb where k='g3'));

-- ════ P5. Plafon habis ════
update public.app_settings set promo_budget_idr_monthly = 0 where id = 'global';
select set_config('request.jwt.claim.sub', 'ed0e0000-0000-4000-8000-0000000000a1', true);
do $$
declare v_msg text := 'no exception';
begin
  begin
    perform public.send_gift('[TEST]-pb-m1f1', 'ed0e0000-0000-4000-8000-0000000000f1', 'rose');
  exception when others then v_msg := sqlerrm; end;
  insert into _pb values ('g4', v_msg);
end $$;
select supabase_tests.check('P5: plafon habis → gift dari bonus ditolak',
  (select v from _pb where k='g4') <> 'no exception', (select v from _pb where k='g4'));
select supabase_tests.check('P5: plafon habis → hadiah misi female jadi bonus',
  public._mission_payout_eligible('ed0e0000-0000-4000-8000-0000000000f1', null) = 'promo_budget');

select supabase_tests.check('helper promo tidak executable authenticated',
  not has_function_privilege('authenticated',
        'public.ledger_spend_promo(uuid,text,integer,text,uuid,integer)', 'execute')
  and not has_function_privilege('authenticated',
        'public.yukcoin_spendable(uuid,uuid,integer)', 'execute'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
