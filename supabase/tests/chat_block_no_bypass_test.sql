-- Lapis 3: blokir berlaku juga untuk admin/service_role (20261023100000).
-- Jalankan: scripts/run_sql_tests.sh chat_block_no_bypass_test.sql
-- Transaksional (begin/rollback) — data produksi tak berubah. Hanya akun
-- dummy test (mk_dummy), tidak menyentuh user asli.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b1'::uuid, '[TEST] BlokirA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b2'::uuid, '[TEST] BlokirB', 'online');

insert into public.private_chats (chat_id, participants)
values ('[TEST]-blk-ab', array['d0c1e000-0000-4000-8000-0000000000b1','d0c1e000-0000-4000-8000-0000000000b2']::uuid[]);

-- B memblokir A.
insert into public.blocks (blocker_id, blocked_id)
values ('d0c1e000-0000-4000-8000-0000000000b2', 'd0c1e000-0000-4000-8000-0000000000b1');

select supabase_tests.check('body trigger tanpa pengecualian is_admin_request',
  position('is_admin_request' in pg_get_functiondef('public.enforce_chat_block()'::regprocedure)) = 0);

create temp table _blk_res (who text, ditolak boolean) on commit drop;
grant all on _blk_res to service_role;

-- Sebagai service_role (jalur ai-reply / admin) → WAJIB ditolak 'blocked'.
set local role service_role;
do $$
begin
  insert into public.private_messages (chat_id, sender_id, text, type)
  values ('[TEST]-blk-ab', 'd0c1e000-0000-4000-8000-0000000000b1', '[TEST] tembus?', 'text');
  insert into _blk_res values ('service_role', false);
exception when others then
  insert into _blk_res values ('service_role', sqlerrm = 'blocked');
end $$;
reset role;

select supabase_tests.check('service_role kirim ke pemblokir → ditolak trigger',
  coalesce((select ditolak from _blk_res where who = 'service_role'), false));

select supabase_tests.report() as result;
rollback;
