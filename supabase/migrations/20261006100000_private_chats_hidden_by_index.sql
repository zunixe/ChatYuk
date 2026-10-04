-- ============================================================
-- PERF: index GIN untuk private_chats.hidden_by.
--
-- `getHiddenChats` (chat_service_private_chatlist) query
--   select chat_id from private_chats where hidden_by @> array[myUid]
-- Tanpa index → SEQ SCAN seluruh private_chats (terukur: 1728 rows,
-- "Rows Removed by Filter: 1728"). Kecil sekarang (~1ms) tapi tumbuh
-- linear seiring jumlah chat → makin lambat.
--
-- Index GIN SAMA seperti pinned_by/muted_by/archived_by (pola konsisten).
-- Catatan: latensi RPC 900ms di HP yang dilaporkan BUKAN karena query ini
-- (server 1.2ms) — itu network. Index ini pencegahan agar tetap cepat saat
-- data besar.
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

create index if not exists idx_private_chats_hidden_by
  on public.private_chats using gin (hidden_by);
