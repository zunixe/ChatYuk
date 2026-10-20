-- Metadata KUTIPAN BALASAN (reply quote ala WhatsApp).
--
-- Latar: kutipan balasan dulu hanya menyimpan TEKS (`replied_to_text`). Untuk
-- pesan MEDIA (foto/video/lokasi/stiker/dll) teksnya kosong, sehingga kutipan
-- tidak tampil sama sekali. WhatsApp selalu menampilkan nama + ikon jenis +
-- THUMBNAIL kecil di sisi kanan bubble.
--
-- `replied_to_meta` menyimpan JSON ringkas (lihat core/chat/reply_meta.dart):
--   { "t": "<type pesan>", "id": "<id pesan asli>", "w": <lebar>, "h": <tinggi>,
--     "p": "<path video>", "d": "<chat key cache>" }
-- Thumbnail TIDAK disimpan di server — klien mengambilnya dari cache lokal
-- pesan asli (PhotoCache) / poster video. Baris lama = NULL (aman, kutipan
-- jatuh ke mode teks seperti sebelumnya).
--
-- Idempotent: aman dijalankan berulang.

alter table if exists public.private_messages
  add column if not exists replied_to_meta jsonb;

alter table if exists public.messages
  add column if not exists replied_to_meta jsonb;
