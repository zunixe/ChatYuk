-- ============================================================
-- Video "sekali lihat": type video_once + video_once_expired.
--
-- LATAR: video chat memakai kolom `duration_ms` untuk PANJANG VIDEO (wajib
-- untuk playback) — beda dari foto yang memakai duration_ms sebagai timer
-- view-once (0 = sampai ditutup, N = countdown). Karena itu video view-once
-- TIDAK BISA menumpang duration_ms: dua makna bertabrakan.
--
-- SOLUSI: tandai lewat TYPE (sejajar pola image/view_once):
--   'video'              = video biasa
--   'video_once'         = video sekali lihat (belum ditonton)
--   'video_once_expired' = sudah ditonton → TERKUNCI (kontrol di UI,
--                          image_data DIBIARKAN agar admin tetap bisa lihat
--                          — persis perilaku view_once_expired foto).
--
-- duration_ms tetap = panjang video (ms) untuk KETIGA type di atas.
--
-- Dasar: 20260926130000_private_chat_video_type.sql (constraint terakhir).
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check
  check (type = any (array[
    'text'::text, 'image'::text, 'view_once'::text, 'view_once_expired'::text,
    'coin'::text, 'gift'::text, 'call'::text, 'voice'::text,
    'video'::text, 'video_once'::text, 'video_once_expired'::text
  ]));
