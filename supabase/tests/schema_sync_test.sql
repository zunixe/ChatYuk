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

-- ── FROZEN: admin (paling sering di-replace: 18× & 12×) ──
select supabase_tests.check('admin_list_dummies() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_list_dummies'));
select supabase_tests.check('admin_stats_detail() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_stats_detail'));
select supabase_tests.check('admin_excluded_uids() ada (helper exclude)',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_excluded_uids'));

-- ── FROZEN: feed / sosial ──
select supabase_tests.check('create_story() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='create_story'));
select supabase_tests.check('follow_count_sync() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='follow_count_sync'));
select supabase_tests.check('nearby_users() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='nearby_users'));
-- Story: kolom slide + tabel views (dipakai tray & viewer).
select supabase_tests.check('tabel stories + story_views ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='stories')
  and exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='story_views'));

-- ── Privacy (20260920130000 + fixes 20260920130001) ──
select supabase_tests.check('kolom privacy profiles ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='presence_visibility')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='last_seen_visibility')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='profile_photo_visibility')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='about_visibility')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='story_visibility')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='read_receipts_enabled'));
select supabase_tests.check('tabel profile_privacy_exclusions ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='profile_privacy_exclusions'));
select supabase_tests.check('RPC privacy lengkap',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='my_privacy_settings')
  and exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='update_privacy_settings')
  and exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='replace_privacy_exclusions')
  and exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='privacy_can_view')
  and exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='profile_public')
  and exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='privacy_friends'));
select supabase_tests.check('mark_chat_read() return jsonb (privacy-aware)',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='mark_chat_read'
           and p.prorettype = 'jsonb'::regtype));
select supabase_tests.check('nearby_users() urut jarak (bukan ordinal salah)',
  (select pg_get_functiondef(p.oid) like '%order by 11 asc%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='nearby_users' limit 1));
select supabase_tests.check('get_online_users() tetap boleh anon',
  exists(select 1 from pg_proc p
         where p.proname='get_online_users' and has_function_privilege('anon', p.oid, 'execute')));

select supabase_tests.report() as result;
rollback;
