-- ============================================================
-- Optimasi index: perbaiki drift + buang duplikat PERSIS.
--
-- Aman: TIDAK mengubah hasil query apa pun, tidak menyentuh fungsi,
-- tidak menyentuh grant/RLS. Hanya index (kecepatan, bukan semantik).
--
-- Dasar audit LIVE DB (pg_indexes + pg_index + pg_stat_user_indexes,
-- stats_reset 2026-07-24):
--   1. private_chats: idx_private_chats_participants_gin
--                     DAN private_chats_participants_gin_idx
--      → definisi IDENTIK: USING gin (participants) = duplikat persis.
--   2. story_views: CATATAN — idx_story_views_story_viewer btree(story_id,viewer_id)
--      memang kolomnya = story_views_pkey UNIQUE, TETAPI index itu DIKUNCI
--      oleh supabase/tests/story_test.sql ('index idx_story_views_story_viewer
--      ada') sebagai bagian kontrak. Karena guardrail proyek melarang
--      menghapus yang dikunci test → index ini SENGAJA TIDAK di-drop.
--   3. private_chats: idx_private_chats_last_message_at_desc (btree) ADA di
--      file migrasi 20260829020000 tetapi TIDAK ADA di live → drift.
--      private_chats.idx_scan = 1.7jt (paling sering di-scan) & urutan list
--      chat pakai last_message_at desc → index ini PERLU ditambahkan.
--
-- CATATAN: kolom yang dipakai RLS/grant tidak disentuh sama sekali.
-- Rollback: drop 2 index baru bila perlu (lihat bawah); recreate 2 index
-- yang di-drop dari definisi di baris komentar `-- ROLLBACK:`.
-- ============================================================

-- ── 1. Perbaiki drift: index urutan last_message_at (additive) ──────────────
-- Kolom sama yang sudah dipakai query list chat (ORDER BY last_message_at DESC).
-- Idempotent.
create index if not exists idx_private_chats_last_message_at_desc
  on public.private_chats (last_message_at desc);

-- ── 2. Buang duplikat PERSIS (semantik identik, hanya hemat write/space) ────
-- ROLLBACK: CREATE INDEX private_chats_participants_gin_idx
--             ON public.private_chats USING gin (participants);
drop index if exists public.private_chats_participants_gin_idx; -- SAFE: duplikat persis idx_private_chats_participants_gin (gin participants); dipakai via planner, tidak ada query yang menyebut namanya.

-- CATATAN: idx_story_views_story_viewer TIDAK di-drop — dikunci oleh
-- supabase/tests/story_test.sql (kontrak). Pkey menutupinya secara teknis,
-- tapi menghapusnya melanggar guardrail test. Dibiarkan.

-- Verifikasi (jalankan manual setelah apply):
--   select indexname from pg_indexes where schemaname='public'
--     and indexname in ('idx_private_chats_last_message_at_desc',
--                       'private_chats_participants_gin_idx',
--                       'idx_story_views_story_viewer');
--   → idx_private_chats_last_message_at_desc & idx_story_views_story_viewer
--     ADA; private_chats_participants_gin_idx HILANG.
