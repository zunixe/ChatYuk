-- Daftar kata terlarang nickname → dipindah dari APK ke DB
-- (REVIEW_2026-10-24 BUG-05, P3).
--
-- Sebelumnya daftar ('zaini','hafid') HARDCODE di `lib/utils.dart`:
--   (a) nama pribadi tersemat di APK yang bisa dibongkar,
--   (b) mengubah daftar wajib rilis baru.
--
-- Sekarang klien membaca `app_settings.banned_nicknames` saat startup
-- (lib/core/chat/banned_nicknames.dart). Bila gagal dimuat (offline / kolom
-- belum ada), klien memakai daftar BAWAAN yang sama — guard anti-impersonasi
-- tidak pernah terbuka hanya karena jaringan bermasalah.
--
-- Nilai default = daftar lama (tidak mengubah perilaku sampai admin mengubah).
--
-- SAFE: hanya MENAMBAH satu kolom aditif + grant SELECT kolom itu.
--       Tabel bersama `app_settings` dibaca klien untuk flag fitur; grant
--       hanya pada kolom baru (bukan SELECT *), jadi kolom sensitif
--       (`app_shared_secret`, dst.) tetap tertutup. Fitur terdampak:
--       validasi nickname saat registrasi/ubah profil (nilai sama seperti
--       sebelumnya).
alter table public.app_settings
  add column if not exists banned_nicknames text[]
  not null default array['zaini', 'hafid'];

-- SAFE: grant SELECT hanya pada kolom `banned_nicknames` (bukan seluruh baris).
--       anon dibutuhkan karena validasi nickname juga terjadi SEBELUM login
--       (layar entry). Tidak ada data sensitif di kolom ini.
grant select (banned_nicknames) on public.app_settings to anon, authenticated; -- SAFE: hanya kolom baru banned_nicknames; dibutuhkan anon karena validasi nickname juga jalan sebelum login (layar entry). Tidak ada data sensitif.
