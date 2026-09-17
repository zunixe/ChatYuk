-- Lapis 3: invariant fitur yang PERNAH hilang karena migrasi belum ter-apply.
-- Melindungi mute/archive chat, room gift, room mute, dummy kind.
begin;
select supabase_tests.begin_tests();

-- ── Mute & arsip chat (20260909000000) ──
select supabase_tests.check('kolom private_chats.muted_by ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='private_chats' and column_name='muted_by'));
select supabase_tests.check('kolom private_chats.archived_by ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='private_chats' and column_name='archived_by'));
select supabase_tests.check('RPC mute_private_chat ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='mute_private_chat'));
select supabase_tests.check('RPC archive_private_chat ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='archive_private_chat'));

-- ── Room gift (20260908000000) ──
select supabase_tests.check('RPC send_room_gift ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='send_room_gift'));

-- ── Room mute server (20260914120000, C1) ──
select supabase_tests.check('kolom rooms.muted_by ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='rooms' and column_name='muted_by'));
select supabase_tests.check('RPC mute_room ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='mute_room'));

-- ── Dummy kind (20260914110000) ──
select supabase_tests.check('kolom dummy_accounts.kind ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='dummy_accounts' and column_name='kind'));

-- ── Kolom yang TIDAK boleh dipakai lagi (sudah diselaraskan kode) ──
-- messages memakai created_at, bukan inserted_at.
select supabase_tests.check('messages pakai created_at (bukan inserted_at)',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='messages' and column_name='created_at')
  and not exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='messages' and column_name='inserted_at'));

-- ── Reaksi + bintang + teruskan ala WA (20260917000000) ──
select supabase_tests.check('tabel message_reactions ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='message_reactions'));
select supabase_tests.check('tabel starred_messages ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='starred_messages'));
select supabase_tests.check('kolom private_messages.is_forwarded ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='private_messages' and column_name='is_forwarded'));
select supabase_tests.check('kolom messages.is_forwarded ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='messages' and column_name='is_forwarded'));

select supabase_tests.report() as result;
rollback;
