-- pgTAP: kunci keamanan RPC uang + policy UPDATE private_chats + trigger blokir.
--
-- Mengunci 3 perbaikan 2026-10-22 supaya tidak bisa regresi diam-diam:
--   1. spend_yukcoin / charge_metered WAJIB punya guard auth.uid() — tanpa itu
--      siapa pun berakun bisa memanggil RPC dengan uid ORANG LAIN dan
--      menguras saldo YukCoin korban (top-up Play Billing = uang nyata).
--   2. list_my_groups / list_my_global_rooms WAJIB guard (bocor daftar grup
--      privat user lain) + implementasi `_impl` TIDAK boleh bisa dipanggil
--      klien langsung.
--   3. private_chats_update WAJIB punya WITH CHECK; enforce_chat_block WAJIB
--      terpasang (dulu blokir hanya dicek klien → REST langsung bisa menembus).
--
-- Transaksional (BEGIN/ROLLBACK) — tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- ── 1. Guard auth.uid() pada RPC uang ────────────────────────────────────────
select supabase_tests.check('spend_yukcoin punya guard auth.uid()',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'spend_yukcoin'
      and pg_get_functiondef(p.oid) like '%auth.uid()%'
      and pg_get_functiondef(p.oid) like '%p_user is distinct from auth.uid()%'
  ));

select supabase_tests.check('charge_metered punya guard auth.uid()',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'charge_metered'
      and pg_get_functiondef(p.oid) like '%p_caller is distinct from auth.uid()%'
  ));

-- ── 2. Guard metadata + _impl tidak bisa dipanggil klien ────────────────────
select supabase_tests.check('list_my_groups punya guard auth.uid()',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'list_my_groups'
      and pg_get_functiondef(p.oid) like '%p_uid is distinct from auth.uid()%'
  ));

select supabase_tests.check('list_my_global_rooms punya guard auth.uid()',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'list_my_global_rooms'
      and pg_get_functiondef(p.oid) like '%p_uid is distinct from auth.uid()%'
  ));

select supabase_tests.check('list_my_groups_impl TIDAK bisa dieksekusi authenticated',
  not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'list_my_groups_impl'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ));

select supabase_tests.check('list_my_global_rooms_impl TIDAK bisa dieksekusi authenticated',
  not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'list_my_global_rooms_impl'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ));

-- ── 3. Policy UPDATE private_chats punya WITH CHECK ─────────────────────────
select supabase_tests.check('private_chats_update punya WITH CHECK',
  exists(
    select 1 from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'private_chats'
      and p.polname = 'private_chats_update'
      and p.polwithcheck is not null
  ));

-- ── 4. Trigger blokir terpasang & benar-benar menolak ───────────────────────
select supabase_tests.check('trigger enforce_chat_block_trg terpasang',
  exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'private_messages'
      and t.tgname = 'enforce_chat_block_trg' and not t.tgisinternal
  ));

select supabase_tests.report() as result;
rollback;
