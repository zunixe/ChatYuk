-- Lapis 3: My Level — level dari kumulatif topup (male only),
-- reward naik-level idempoten, guard gender & kill-switch ekonomi.
-- Jalankan: scripts/run_sql_tests.sh my_level_test.sql
-- Transaksional (begin/rollback) — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c5e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] LvM1', 'online');
select supabase_tests.mk_dummy('d0c5e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] LvF1', 'online');
update public.profiles set gender = 'male'
 where id = 'd0c5e000-0000-4000-8000-0000000000a1';
update public.profiles set gender = 'female'
 where id = 'd0c5e000-0000-4000-8000-0000000000a2';

create temp table _ml (k text primary key, v text) on commit drop;
grant all on _ml to service_role;

-- ── 0. Anon ditolak ──
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.get_my_level();
  insert into _ml values ('anon', 'lolos');
exception when others then
  insert into _ml values ('anon', sqlerrm);
end $$;
select supabase_tests.check('anon → Not authenticated',
  (select v from _ml where k = 'anon') = 'Not authenticated',
  (select v from _ml where k = 'anon'));

-- ── 1. Tanpa topup → level 0, ladder 11 entri, next = Lv.1 @700 ──
select set_config('request.jwt.claim.sub',
                  'd0c5e000-0000-4000-8000-0000000000a1', true);
insert into _ml values ('lv0', public.get_my_level()::text);
select supabase_tests.check('saldo kosong → level 0',
  (select v::jsonb->>'level' from _ml where k = 'lv0') = '0');
select supabase_tests.check('ladder 11 entri (Lv.0–Lv.10)',
  (select jsonb_array_length(v::jsonb->'ladder') from _ml where k = 'lv0') = 11);
select supabase_tests.check('next_level = 1, next_at = 700',
  (select v::jsonb->>'next_level' from _ml where k = 'lv0') = '1'
  and (select v::jsonb->>'next_at' from _ml where k = 'lv0') = '700');

-- ── 2. Topup 700 → Lv.1 + reward +50 sekali ──
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('d0c5e000-0000-4000-8000-0000000000a1', 'topup', 'topup', 700, 'test-lv-1');
-- Level dihitung dari order paid (20261110020000).
insert into public.topup_orders (id, user_id, package_id, coins, price_idr, status, provider, platform, paid_at)
values ('test-lv-1', 'd0c5e000-0000-4000-8000-0000000000a1', (select id from public.topup_packages order by price_idr limit 1), 700, 0, 'paid', 'test', 'play', now());
insert into _ml values ('lv1', public.get_my_level()::text);
select supabase_tests.check('kumulatif 700 → level 1',
  (select v::jsonb->>'level' from _ml where k = 'lv1') = '1');
select supabase_tests.check('reward Lv.1 = +50 dicetak',
  (select v::jsonb->'just_rewarded'->0->>'coins' from _ml where k = 'lv1') = '50');
select supabase_tests.check('reward masuk bucket bonus type level_reward',
  exists(select 1 from public.coin_ledger
          where user_id = 'd0c5e000-0000-4000-8000-0000000000a1'
            and bucket = 'bonus' and type = 'level_reward'
            and amount = 50 and ref_id = 'level_1'));

-- ── 3. Idempoten: panggil ulang → tidak dobel reward ──
insert into _ml values ('lv1b', public.get_my_level()::text);
select supabase_tests.check('panggil ulang → just_rewarded kosong',
  (select jsonb_array_length(v::jsonb->'just_rewarded') from _ml where k = 'lv1b') = 0);
select supabase_tests.check('baris level_reward Lv.1 tetap 1',
  (select count(*) from public.coin_ledger
    where user_id = 'd0c5e000-0000-4000-8000-0000000000a1'
      and type = 'level_reward' and ref_id = 'level_1') = 1);

-- ── 4. Bucket earned/bonus & spend topup TIDAK mengubah level ──
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
 ('d0c5e000-0000-4000-8000-0000000000a1', 'earned', 'test_seed', 100000, 'test-lv-e'),
 ('d0c5e000-0000-4000-8000-0000000000a1', 'bonus',  'test_seed', 50000, 'test-lv-b'),
 ('d0c5e000-0000-4000-8000-0000000000a1', 'topup',  'spend',     -300,  'test-lv-s');
insert into _ml values ('lv1c', public.get_my_level()::text);
select supabase_tests.check('earned/bonus/spend tidak mengubah kumulatif (700 → Lv.1)',
  (select v::jsonb->>'level' from _ml where k = 'lv1c') = '1'
  and (select v::jsonb->>'cumulative' from _ml where k = 'lv1c') = '700');

-- ── 5. Naik ke Lv.2 (kumulatif 2000) → reward +100 ──
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('d0c5e000-0000-4000-8000-0000000000a1', 'topup', 'topup', 1300, 'test-lv-2');
-- Level dihitung dari order paid (20261110020000).
insert into public.topup_orders (id, user_id, package_id, coins, price_idr, status, provider, platform, paid_at)
values ('test-lv-2', 'd0c5e000-0000-4000-8000-0000000000a1', (select id from public.topup_packages order by price_idr limit 1), 1300, 0, 'paid', 'test', 'play', now());
insert into _ml values ('lv2', public.get_my_level()::text);
select supabase_tests.check('kumulatif 2000 → level 2',
  (select v::jsonb->>'level' from _ml where k = 'lv2') = '2');
select supabase_tests.check('reward Lv.2 = +100',
  (select v::jsonb->'just_rewarded'->0->>'coins' from _ml where k = 'lv2') = '100');

-- ── 6. Badge user lain: male terbaca, female = 0 ──
insert into _ml values ('ulvl', public.get_user_level('d0c5e000-0000-4000-8000-0000000000a1')::text);
select supabase_tests.check('get_user_level(male) → 2',
  (select v::jsonb->>'level' from _ml where k = 'ulvl') = '2');
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('d0c5e000-0000-4000-8000-0000000000a2', 'topup', 'topup', 999999, 'test-lv-f');
-- Level dihitung dari order paid (20261110020000).
insert into public.topup_orders (id, user_id, package_id, coins, price_idr, status, provider, platform, paid_at)
values ('test-lv-f', 'd0c5e000-0000-4000-8000-0000000000a2', (select id from public.topup_packages order by price_idr limit 1), 999999, 0, 'paid', 'test', 'play', now());
insert into _ml values ('ulvf', public.get_user_level('d0c5e000-0000-4000-8000-0000000000a2')::text);
select supabase_tests.check('get_user_level(female) → 0 (male only)',
  (select v::jsonb->>'level' from _ml where k = 'ulvf') = '0');

-- ── 7. Kill-switch ekonomi: points_enabled=false → level jalan, reward tidak ──
update public.app_settings set points_enabled = false where id = 'global';
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
values ('d0c5e000-0000-4000-8000-0000000000a1', 'topup', 'topup', 3000, 'test-lv-3');
-- Level dihitung dari order paid (20261110020000).
insert into public.topup_orders (id, user_id, package_id, coins, price_idr, status, provider, platform, paid_at)
values ('test-lv-3', 'd0c5e000-0000-4000-8000-0000000000a1', (select id from public.topup_packages order by price_idr limit 1), 3000, 0, 'paid', 'test', 'play', now());
insert into _ml values ('lv3off', public.get_my_level()::text);
select supabase_tests.check('kill-switch: level tetap dihitung (5000 → Lv.3)',
  (select v::jsonb->>'level' from _ml where k = 'lv3off') = '3');
select supabase_tests.check('kill-switch: reward Lv.3 TIDAK dicetak',
  (select jsonb_array_length(v::jsonb->'just_rewarded') from _ml where k = 'lv3off') = 0
  and not exists(select 1 from public.coin_ledger
                  where user_id = 'd0c5e000-0000-4000-8000-0000000000a1'
                    and type = 'level_reward' and ref_id = 'level_3'));
update public.app_settings set points_enabled = true where id = 'global';
insert into _ml values ('lv3on', public.get_my_level()::text);
select supabase_tests.check('kill-switch lepas: reward Lv.3 tertunggak dicetak',
  (select v::jsonb->'just_rewarded'->0->>'coins' from _ml where k = 'lv3on') = '150');

-- ── 8. Privilege reward tidak bisa ditarik: withdrawable tetap earned ──
insert into _ml values ('wd', public.get_wallet()::text);
select supabase_tests.check('reward bonus tidak masuk withdrawable',
  (select v::jsonb->>'withdrawable' from _ml where k = 'wd') = '100000');

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
