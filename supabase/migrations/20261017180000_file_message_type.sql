-- Kirim FILE/dokumen di chat (ala WhatsApp) — izinkan type='file'.
--
-- ADITIF: tambah 'file' ke daftar type, TIDAK menghapus nilai lama.
-- Basis = constraint live (sama 20261013120000_sticker_type.sql).
--
-- Penyimpanan (tanpa kolom baru):
--   text        = nama file asli (mis. 'laporan.pdf') → notif push &
--                 last_message otomatis menampilkan nama file (cabang
--                 `else new.text` di fungsi notif/last_message, tak disentuh).
--   image_path  = path storage `chat/<chatId>/<stamp>_f.<ext>` (bucket
--                 chat-photos; policy storage_object_owner_ok sudah
--                 mengizinkan prefix chat/ untuk peserta).
--   duration_ms = ukuran file (byte).

-- 1) Pesan private (1:1)
alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker',
      'file'
    ])
  );

-- 2) Pesan room/grup
alter table public.messages
  drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker',
      'file'
    ])
  );
