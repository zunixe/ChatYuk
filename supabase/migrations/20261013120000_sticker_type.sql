-- Sticker (ala Telegram) — F0: izinkan type='sticker' di pesan.
--
-- ADITIF: tambah 'sticker' ke daftar type, TIDAK menghapus nilai lama
-- (aman utk data eksisting & insert pesan biasa).
--
-- Sticker disimpan spt gambar: `image_path` (path storage bucket
-- `chat-photos`/`stickers/...`) atau `image_data` (base64 utk pending).
-- Kolom tambahan tak diperlukan; metadata jenis sticker (static/animated_
-- webp/webm/tgs) diturunkan dari ekstensi/bytes saat render.

-- 1) Pesan private (1:1)
alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker'
    ])
  );

-- 2) Pesan room/grup
alter table public.messages
  drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker'
    ])
  );
