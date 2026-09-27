-- ============================================================
-- Selaraskan drift: pasang TRIGGER trg_private_msg (samakan dengan PROD)
--
-- Fungsi `handle_new_private_message()` sudah ada & diperbarui beberapa kali
-- (terakhir 20260917180000_last_sender_id.sql — mengisi last_message,
-- last_message_at, last_sender_id, message_count, unread_counts, last_read_at),
-- TETAPI trigger yang memanggilnya (`trg_private_msg` AFTER INSERT) tidak
-- pernah dibuat di file migration mana pun. Di PROD trigger itu ADA
-- (dikonfirmasi via Management API) — dibuat manual.
--
-- Akibat di lokal: pesan yang di-INSERT langsung oleh RPC (mis. send_gift,
-- send_coins) TIDAK meng-update private_chats.last_message → preview/urutan
-- chat list tidak ikut berubah ("hadiah terkirim tapi tidak muncul di chat").
--
-- Migration ini menyamakan lokal dengan prod. Idempotent.
-- ============================================================

drop trigger if exists trg_private_msg on public.private_messages;
create trigger trg_private_msg
  after insert on public.private_messages
  for each row execute function public.handle_new_private_message();
