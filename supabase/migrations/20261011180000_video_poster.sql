-- ============================================================
-- Video chat: kolom `video_poster` — thumbnail (frame 1) yang diunggah
-- pengirim agar PENERIMA melihat preview (bukan kotak hitam) TANPA mengunduh
-- video penuh.
--
-- Latar: WhatsApp menampilkan capture frame video sebagai preview karena
-- thumbnail di-generate di sisi pengirim/server saat upload. ChatYuk punya
-- poster dari pengirim (storyVideoPoster) tapi hanya disimpan lokal di HP
-- pengirim; penerima tak pernah dapat → kartu hitam sampai tap play
-- (unduh penuh).
--
-- Perubahan: kolom `video_poster` (path storage JPEG di bucket chat-photos)
-- pada private_messages + messages (room). Penerima unduh poster KECIL
-- (puluhan KB) → tampil sebagai thumbnail seketika; video penuh tetap hanya
-- saat tap play.
--
-- Postur privasi: poster ikut RLS baris pesan (path di bucket chat-photos
-- yang sudah dijaga guard tipe + ukuran ≤8 MB). Tidak mengubah visibilitas
-- media—hanya menyertakan 1 frame kecil yang memang bagian dari video yang
-- sudah boleh dilihat penerima.
-- ============================================================

alter table public.private_messages
  add column if not exists video_poster text not null default '';

alter table public.messages
  add column if not exists video_poster text not null default '';

comment on column public.private_messages.video_poster is
  'Path storage poster/thumbnail video (JPEG, bucket chat-photos). Diunggah pengirim saat kirim video → penerima tampil preview tanpa unduh video penuh.';
comment on column public.messages.video_poster is
  'Path storage poster/thumbnail video (JPEG, bucket chat-photos). Analog private_messages.video_poster untuk room chat.';
