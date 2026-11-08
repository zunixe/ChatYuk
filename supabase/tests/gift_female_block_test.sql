-- Lapis 3: perempuan TIDAK BISA kirim gift (20261110070000).
--   G1: female dengan saldo earned cukup → send_gift ditolak, saldo utuh.
--   G2: male tetap bisa kirim gift ke female.
-- Transaksional — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('ed0f0000-0000-4000-8000-0000000000a1'::uuid, '[TEST] GF-M1', 'online');
select supabase_tests.mk_dummy('ed0f0000-0000-4000-8000-0000000000f1'::uuid, '[TEST] GF-F1', 'online');
update public.profiles set gender = 'male', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'ed0f0000-0000-4000-8000-0000000000a1';
update public.profiles set gender = 'female', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'ed0f0000-0000-4000-8000-0000000000f1';
update public.app_settings set points_enabled = true, gift_cut_pct = 30
 where id = 'global';

insert into public.private_chats (chat_id, participants) values
  ('[TEST]-gf-m1f1', array['ed0f0000-0000-4000-8000-0000000000a1','ed0f0000-0000-4000-8000-0000000000f1']::uuid[]);
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
  ('ed0f0000-0000-4000-8000-0000000000a1', 'topup', 'topup', 500, '[TEST]gf'),
  ('ed0f0000-0000-4000-8000-0000000000f1', 'earned', 'call_video_income', 500, '[TEST]gf');

create temp table _gf (k text primary key, v text) on commit drop;
grant all on _gf to service_role;

-- ════ G1. Female → ditolak ════
select set_config('request.jwt.claim.sub', 'ed0f0000-0000-4000-8000-0000000000f1', true);
do $$
declare v_msg text := 'no exception';
begin
  begin
    perform public.send_gift('[TEST]-gf-m1f1', 'ed0f0000-0000-4000-8000-0000000000a1', 'rose');
  exception when others then v_msg := sqlerrm; end;
  insert into _gf values ('f', v_msg);
end $$;
select supabase_tests.check('G1: female send_gift → Female cannot send gift',
  (select v from _gf where k='f') like '%Female cannot send gift%',
  (select v from _gf where k='f'));
select supabase_tests.check('G1: tidak ada gift_sent female',
  not exists (select 1 from public.coin_ledger
              where user_id='ed0f0000-0000-4000-8000-0000000000f1' and type='gift_sent'));
select supabase_tests.check('G1: tidak ada pesan gift dari female',
  not exists (select 1 from public.private_messages
              where chat_id='[TEST]-gf-m1f1' and type='gift'
                and sender_id='ed0f0000-0000-4000-8000-0000000000f1'));

-- ════ G2. Male → tetap bisa ════
select set_config('request.jwt.claim.sub', 'ed0f0000-0000-4000-8000-0000000000a1', true);
insert into _gf values ('m',
  public.send_gift('[TEST]-gf-m1f1', 'ed0f0000-0000-4000-8000-0000000000f1', 'rose')::text);
select supabase_tests.check('G2: male send_gift → ok',
  (select (v::jsonb->>'ok')::boolean from _gf where k='m') is true,
  (select v from _gf where k='m'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
