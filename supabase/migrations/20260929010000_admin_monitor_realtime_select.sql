-- ============================================================
-- Monitor chat realtime: izinkan admin SELECT private_messages.
--
-- Latar: layar monitor chat admin (`admin_chat_view_screen`) mendengarkan
-- postgres_changes private_messages (filter chat_id), tapi policy SELECT
-- live hanya untuk peserta chat → Supabase Realtime (tunduk RLS) tidak
-- mengirim event apa pun ke sesi admin → pesan baru hanya muncul via
-- poll 5 dtk (telat 5-10 dtk di HP admin).
-- Admin SUDAH bisa baca semua pesan via RPC security definer
-- (admin_get_chat_messages_page) — policy ini menyamakan hak realtime,
-- tidak memberi akses baru secara substansi.
-- ============================================================

drop policy if exists private_messages_admin_select on public.private_messages; -- SAFE: hapus-buat ulang policy milik migrasi ini sendiri (idempoten); tidak menyentuh policy peserta.
create policy private_messages_admin_select on public.private_messages for select using (public.is_admin_request()); -- SAFE: read-only + hanya admin (zunixe@gmail.com/service_role) agar realtime monitor jalan; user biasa tetap ikut policy peserta; admin sudah baca semua pesan via RPC.
