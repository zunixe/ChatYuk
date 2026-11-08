-- Lapis 3: perempuan TIDAK BISA kirim koin (20261110080000).
--   C1: female dengan saldo earned cukup → send_coins ditolak, saldo utuh.
--   C2: male tetap bisa kirim koin.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed10e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] SC-M1', 'online');
select supabase_tests.mk_dummy('ed10e000-0000-4000-8000-0000000000f1'::uuid, '[TEST] SC-F1', 'online');
update public.profiles set gender = 'male', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'ed10e000-0000-4000-8000-0000000000a1';
update public.profiles set gender = 'female', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'ed10e000-0000-4000-8000-0000000000f1';
update public.app_settings set points_enabled = true where id = 'global';

insert into public.private_chats (chat_id, participants) values
  ('[TEST]-sc-m1f1', array['ed10e000-0000-4000-8000-0000000000a1','ed10e000-0000-4000-8000-0000000000f1']::uuid[]);
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
  ('ed10e000-0000-4000-8000-0000000000a1', 'topup', 'topup', 500, '[TEST]sc'),
  ('ed10e000-0000-4000-8000-0000000000f1', 'earned', 'call_video_income', 500, '[TEST]sc');

create temp table _sc (k text primary key, v text) on commit drop;
grant all on _sc to service_role;

select set_config('request.jwt.claim.sub', 'ed10e000-0000-4000-8000-0000000000f1', true);
do $$
declare v_msg text := 'no exception';
begin
  begin
    perform public.send_coins('[TEST]-sc-m1f1', 'ed10e000-0000-4000-8000-0000000000a1', 10);
  exception when others then v_msg := sqlerrm; end;
  insert into _sc values ('f', v_msg);
end $$;
select supabase_tests.check('C1: female send_coins → Female cannot send coins',
  (select v from _sc where k='f') like '%Female cannot send coins%',
  (select v from _sc where k='f'));
select supabase_tests.check('C1: tidak ada coin_sent female',
  not exists (select 1 from public.coin_ledger
              where user_id='ed10e000-0000-4000-8000-0000000000f1' and type='coin_sent'));

select set_config('request.jwt.claim.sub', 'ed10e000-0000-4000-8000-0000000000a1', true);
insert into _sc values ('m',
  public.send_coins('[TEST]-sc-m1f1', 'ed10e000-0000-4000-8000-0000000000f1', 10)::text);
select supabase_tests.check('C2: male send_coins → ok',
  (select (v::jsonb->>'ok')::boolean from _sc where k='m') is true,
  (select v from _sc where k='m'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
