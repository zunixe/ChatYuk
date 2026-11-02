-- ============================================================
-- 20261101100200_disable_room_gift.sql
-- Gift hanya untuk chat 1:1 (penerimanya jelas: orang yang dituju).
-- Di room/group penerimanya ambigu (host/owner), jadi fitur kirim gift
-- dinonaktifkan total.
--
-- Alasan tambahan: send_room_gift TIDAK PERNAH diperbarui sejak 2026-09-08 —
-- masih menerima bucket `bonus` (koin gratis), tanpa cek registrasi, tanpa
-- rate limit, qty sampai 20. Karena request_withdraw menjumlah semua bucket,
-- ini jalur pencucian bonus → earned (withdrawable). Menutup fungsi ini
-- sekaligus menutup celah tersebut.
--
-- Fungsi TIDAK di-drop: riwayat grant tetap aman, schema_sync_test tetap
-- lulus, dan pesan gift lama tetap bisa dirender (read-only).
-- ============================================================

-- 1. Badan fungsi: langsung tolak (defense in depth, bila grant bocor lagi).
CREATE OR REPLACE FUNCTION public.send_room_gift(
  p_room_id text, p_gift_id text, p_qty int default 1
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'Gift hanya untuk chat pribadi (bukan room/grup)'
    USING ERRCODE = '42501';
END;
$$;

-- 2. Cabut akses client.
-- SAFE: send_room_gift tidak dipakai lagi oleh client (wiring dihapus dari
-- room_chat_live/room_chat_room/chat_provider/chat_service_room).
-- Terdampak: gift room (dinonaktifkan), chat private (pakai send_gift —
-- TIDAK terpengaruh), riwayat pesan gift lama (tetap dirender read-only).
REVOKE EXECUTE ON FUNCTION public.send_room_gift(text, text, int)
  FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.send_room_gift(text, text, int)
  FROM service_role;

-- 3. Riwayat: tidak ada baris 'gift' baru yang boleh dibuat client di room.
-- Pesan lama tetap ada; guard ini hanya mencegah pemalsuan bubble baru
-- tanpa pergerakan ledger. (type 'gift' tetap diizinkan di private_messages
-- untuk gift 1:1 yang sah.)
