-- Lapis 3: REGRESSION test — mengunci insiden nyata yang sudah diperbaiki.
-- Transaksional (BEGIN/ROLLBACK), tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- ── 2026-09-21: fn_archive_deleted_user gagal 23502 saat user tanpa profil ──
-- Akun anon yang sudah dihapus (auth.users ada, profiles tidak) membuat
-- SELECT ... INTO tidak menemukan baris → v_reg NULL → INSERT melanggar
-- NOT NULL deleted_users.is_registered. Fix: coalesce(v_reg,false).
select supabase_tests.check('fn_archive_deleted_user pakai coalesce(is_registered)',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_archive_deleted_user'
      and pg_get_functiondef(p.oid) like '%coalesce(v_reg,false)%'
  ));

-- ── 2026-09-21: hardening profiles TIDAK boleh grant SELECT level-tabel ──
-- Kalau ini bocor (grant penuh dikembalikan), hardening kolom sensitif hilang.
select supabase_tests.check('profiles tanpa SELECT level-tabel untuk authenticated',
  not exists(
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'profiles'
      and grantee = 'authenticated' and privilege_type = 'SELECT'
  ));

-- ── 2026-09-21: mentions room trigger masih terpasang ──
select supabase_tests.check('trigger notify_mention_room_trg terpasang',
  exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'messages'
      and t.tgname = 'notify_mention_room_trg' and not t.tgisinternal
  ));

-- ── 2026-09-21: trigger guard sosial dipasang di DUA tabel dengan kolom
--    berbeda (follows: follower_id/followee_id; friend_requests: from_id/to_id).
--    Versi lama hanya baca follower_id → SEMUA insert/update friend_requests
--    error 42703, membuat _are_friends() selalu false (privacy 'friends' mati).
select supabase_tests.check('_social_registered_guard menangani friend_requests',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = '_social_registered_guard'
      and pg_get_functiondef(p.oid) like '%from_id%'
      and pg_get_functiondef(p.oid) like '%follower_id%'
  ));

-- ── Presence (paling rawan regresi): ai_always_online masih ada di tick ──
select supabase_tests.check('ai_presence_tick memuat cabang ai_always_online',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'ai_presence_tick'
      and pg_get_functiondef(p.oid) like '%ai_always_online%'
  ));

select supabase_tests.report() as result;
rollback;
