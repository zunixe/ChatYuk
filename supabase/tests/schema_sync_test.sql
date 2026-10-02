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
-- Admin melihat SEMUA user: excluded DIBIARKAN + ditandai flag 'excluded'
-- (kebijakan 2026-09-27; sebelumnya excluded dibuang total).
select supabase_tests.check('admin_stats_detail() tandai excluded (bukan buang)',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_stats_detail'
           and pg_get_functiondef(p.oid) like '%''excluded'', (id = any(v_excl))%'
           and pg_get_functiondef(p.oid) not like '%not (id = any(v_excl))%'));
select supabase_tests.check('admin_stats_users_page() BUANG excluded (kebijakan 2026-10-01)',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_stats_users_page'
           and pg_get_functiondef(p.oid) like '%not (p.id = any(v_excl))%'));

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
-- Privasi nearby (20260922140000): filter blokir + gate berbagi simetris.
select supabase_tests.check('nearby_users() filter blocks (blokir tak muncul)',
  (select pg_get_functiondef(p.oid) like '%public.blocks%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='nearby_users' limit 1));
-- nearby_users (20260928100000 "show all with location"): gate
-- `share_location=true` DUA ARAH DIHAPUS atas keputusan produk — di produksi
-- hanya ~24/231 user share_location=true dan hanya 1 yang eligible online,
-- sehingga "Orang Sekitar" nyaris selalu kosong. Sekarang: tampilkan semua
-- user yang PUNYA koordinat lat/lon, tanpa wajib menekan "bagikan lokasi".
-- Yang dipertahankan: punya lat/lon, status online/idle <= 30 menit,
-- privacy presence, blokir dua arah, exclude admin.
select supabase_tests.check('nearby_users() TIDAK lagi wajib share_location (keputusan produk)',
  (select pg_get_functiondef(p.oid) not like '%Share required%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='nearby_users' limit 1));
select supabase_tests.check('nearby_users() tetap butuh koordinat (viewer & target)',
  (select pg_get_functiondef(p.oid) like '%my_lat%'
      and pg_get_functiondef(p.oid) like '%lat%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='nearby_users' limit 1));
select supabase_tests.check('nearby_users() hormati privacy presence',
  (select pg_get_functiondef(p.oid) like '%privacy_can_view%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='nearby_users' limit 1));
select supabase_tests.check('get_online_users() filter blocks',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='get_online_users'
           and pg_get_functiondef(p.oid) like '%public.blocks%'));
select supabase_tests.check('get_online_users() tetap boleh anon',
  exists(select 1 from pg_proc p
         where p.proname='get_online_users' and has_function_privilege('anon', p.oid, 'execute')));
select supabase_tests.check('get_online_users() kirim about + hormati about_visibility',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='get_online_users'
           and pg_get_functiondef(p.oid) like '%about_ok%'
           and pg_get_functiondef(p.oid) like '%about_visibility%'));
select supabase_tests.check('presence_for() kirim about + hormati about_visibility',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='presence_for'
           and pg_get_functiondef(p.oid) like '%about%'));

-- Retensi user_location_history (anti-drift skala).
select supabase_tests.check('purge_location_history_90d() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='purge_location_history_90d'));
select supabase_tests.check('cron purge-location-history-90d terjadwal',
  exists(select 1 from cron.job where jobname='purge-location-history-90d'));

-- ── REGRESI 2026-09-28: hardening REVOKE menyapu fungsi admin yang MASIH
-- dipanggil app admin → 42501 permission denied (admin_sweep_calls,
-- admin_registrations_daily, admin_contact_*, admin_set_privacy_bypass).
-- Fungsi ini WAJIB tetap EXECUTE-able oleh `authenticated` (guard
-- zunixe@gmail.com ada DI DALAM fungsi). anon tetap dilarang.
select supabase_tests.check('authenticated boleh EXECUTE admin_sweep_calls',
  has_function_privilege('authenticated', 'public.admin_sweep_calls()', 'EXECUTE'));
select supabase_tests.check('anon TIDAK boleh EXECUTE admin_sweep_calls',
  not has_function_privilege('anon', 'public.admin_sweep_calls()', 'EXECUTE'));
select supabase_tests.check('authenticated boleh EXECUTE admin_registrations_daily',
  has_function_privilege('authenticated', 'public.admin_registrations_daily(integer,integer)', 'EXECUTE'));
select supabase_tests.check('authenticated boleh EXECUTE admin_contact_messages_page',
  has_function_privilege('authenticated', 'public.admin_contact_messages_page(integer,integer)', 'EXECUTE'));
select supabase_tests.check('authenticated boleh EXECUTE admin_contact_set_read',
  has_function_privilege('authenticated', 'public.admin_contact_set_read(uuid,boolean)', 'EXECUTE'));
select supabase_tests.check('authenticated boleh EXECUTE admin_contact_delete',
  has_function_privilege('authenticated', 'public.admin_contact_delete(uuid)', 'EXECUTE'));
select supabase_tests.check('authenticated boleh EXECUTE admin_set_privacy_bypass',
  has_function_privilege('authenticated', 'public.admin_set_privacy_bypass(boolean)', 'EXECUTE'));
select supabase_tests.check('authenticated boleh EXECUTE admin_storage_stats',
  has_function_privilege('authenticated', 'public.admin_storage_stats()', 'EXECUTE'));

-- ── Insight registrasi CEO (migrasi 20261005010000) ──
select supabase_tests.check('admin_registration_kpis() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_registration_kpis'));
select supabase_tests.check('authenticated boleh EXECUTE admin_registration_kpis',
  has_function_privilege('authenticated', 'public.admin_registration_kpis()', 'EXECUTE'));
select supabase_tests.check('anon TIDAK boleh EXECUTE admin_registration_kpis',
  not has_function_privilege('anon', 'public.admin_registration_kpis()', 'EXECUTE'));
select supabase_tests.check('admin_registrations_monthly() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_registrations_monthly'));
select supabase_tests.check('authenticated boleh EXECUTE admin_registrations_monthly',
  has_function_privilege('authenticated', 'public.admin_registrations_monthly(integer)', 'EXECUTE'));

-- ── Top Aktif (leaderboard keaktifan, migrasi 20261005030000) ──
select supabase_tests.check('activity_leaderboard() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='activity_leaderboard'));
select supabase_tests.check('authenticated boleh EXECUTE activity_leaderboard',
  has_function_privilege('authenticated', 'public.activity_leaderboard(text,integer,integer)', 'EXECUTE'));
select supabase_tests.check('anon TIDAK boleh EXECUTE activity_leaderboard',
  not has_function_privilege('anon', 'public.activity_leaderboard(text,integer,integer)', 'EXECUTE'));

-- ── Fake GPS lanjutan (migrasi 20261005040000) ──
select supabase_tests.check('admin_flag_shared_locations() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_flag_shared_locations'));
select supabase_tests.check('anon TIDAK boleh EXECUTE admin_flag_shared_locations',
  not has_function_privilege('anon', 'public.admin_flag_shared_locations(integer)', 'EXECUTE'));
select supabase_tests.check('update_my_location punya heuristik shared_coord',
  (select pg_get_functiondef(p.oid) like '%shared_coord%'
     and pg_get_functiondef(p.oid) like '%static_coord%'
     and pg_get_functiondef(p.oid) like '%known_emulator%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='update_my_location'
   limit 1));


-- ── REGRESI 2026-09-29: cleanup_stale_anonymous gagal total (1.597 akun anon
-- stale menumpuk) karena (a) hapus coin_ledger/point_events wajib matikan
-- trigger append-only sebelum delete auth.users, dan (b) user_devices /
-- user_location_history wajib dihapus SEBELUM profiles (FK SET NULL vs kolom
-- NOT NULL → 23503). Loop juga WAJIB punya exception per-user.
select supabase_tests.check('cleanup_stale_anonymous tangani coin_ledger (append-only)',
  (select pg_get_functiondef(p.oid) like '%coin_ledger_no_delete%'
     and pg_get_functiondef(p.oid) like '%disable trigger coin_ledger_no_delete%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='cleanup_stale_anonymous' limit 1));
select supabase_tests.check('cleanup_stale_anonymous hapus devices sebelum profiles',
  (select pg_get_functiondef(p.oid) like '%delete from public.user_devices%'
     and pg_get_functiondef(p.oid) like '%delete from public.user_location_history%'
     and pg_get_functiondef(p.oid) like '%exception when others%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='cleanup_stale_anonymous' limit 1));

select supabase_tests.report() as result;
rollback;
