-- Batasi bucket chat-photos: ukuran maksimum + allowlist MIME.
-- Latar: bucket sebelumnya tanpa file_size_limit & allowed_mime_types, sehingga
-- contentType dari klien (bisa dipalsukan) diterima apa adanya.
--
-- MIME allowlist HARUS memuat application/octet-stream: aplikasi mobile
-- mengirim dokumen berekstensi tak dikenal dengan contentType fallback
-- (lihat lib/core/chat/chat_file.dart -> ChatFile.mimeOf).
--
-- JUGA WAJIB (sempat terlewat → upload ditolak 400 di device):
--   * image/svg+xml          — stiker Telegram `.tgs` (klien mengirim
--                              content-type hasil lookupMimeType(path), dan
--                              `.tgs` dipetakan ke image/svg+xml).
--   * image/svg+xml-compressed
--   * application/gzip       — payload `.tgs` (gzip) bila dikirim mentah.
--   * audio/m4a              — voice note (StoragePhotoService.uploadVoice
--                              mengirim contentType 'audio/m4a', bukan mp4).
-- SAFE: hanya mengubah metadata bucket storage, tidak menyentuh RLS policy
--       maupun tabel bersama (profiles/private_chats/private_messages/messages).
update storage.buckets
   set file_size_limit   = 52428800,  -- 50 MiB (sama dengan storage.file_size_limit global)
       allowed_mime_types = array[
         'image/jpeg','image/png','image/gif','image/webp',
         'image/svg+xml','image/svg+xml-compressed',
         'video/mp4','video/quicktime','video/webm',
         'audio/mpeg','audio/mp4','audio/m4a','audio/wav','audio/webm',
         'audio/ogg','application/gzip',
         'application/pdf','application/zip',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation',
         'text/plain','text/csv',
         -- fallback mobile untuk ekstensi tak dikenal (JANGAN dihapus)
         'application/octet-stream'
       ]
 where id = 'chat-photos';

-- Sticker Telegram (.tgs = gzip JSON) diunggah sebagai file mentah TANPA
-- fileOptions → content-type mengikuti ekstensi path (image/svg+xml), bukan
-- octet-stream. Karena itu image/svg+xml & application/gzip ada di allowlist.
