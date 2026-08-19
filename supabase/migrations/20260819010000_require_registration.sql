-- ============================================================
-- ChatYuk: Toggle "wajib registrasi" (hilangkan mulai chat tanpa daftar)
-- Ketika aktif, halaman pertama hanya menampilkan Login Google + Daftar Email
-- (form mulai chat sekarang / akun tamu disembunyikan).
-- ============================================================

alter table public.app_settings
  add column if not exists require_registration boolean not null default false;
