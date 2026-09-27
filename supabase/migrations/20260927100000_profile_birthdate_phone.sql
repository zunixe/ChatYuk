-- ============================================================
-- Profil: Tanggal Lahir ASLI + Nomor HP.
--
-- LATAR: kolom `profiles` hanya punya `age` (integer, diisi saat daftar).
-- User ingin menyimpan TANGGAL LAHIR sebenarnya + nomor HP di
-- Pengaturan › Akun (data kontak akun, bukan data sosial publik).
--
-- PERUBAHAN (2 kolom baru, keduanya nullable):
--   1) birth_date date  — tanggal lahir asli (UI date picker).
--   2) phone text       — nomor HP (dinormalisasi ke digit + '+' opsional).
--
-- PRIVASI: kedua kolom TIDAK ditambahkan ke RPC publik apa pun
-- (get_online_users/presence_for/story_*/nearby_* tetap tanpa kolom ini).
-- Hanya pemilik baris yang membacanya (RLS profiles_select berbasis
-- auth.uid) — jadi tidak bocor ke user lain.
--
-- Idempotent. Tidak menyentuh fungsi FROZEN. CARA APPLY: Management API.
-- ============================================================

alter table public.profiles
  add column if not exists birth_date date;

alter table public.profiles
  add column if not exists phone text;

-- Batas kewarasan: tanggal lahir tidak di masa depan & tidak sebelum 1900.
alter table public.profiles
  drop constraint if exists profiles_birth_date_sane;
alter table public.profiles
  add constraint profiles_birth_date_sane
  check (
    birth_date is null
    or (birth_date <= current_date and birth_date >= date '1900-01-01')
  );

-- Nomor HP: hanya digit/'+' , panjang 6..20 (longgar, lintas negara).
alter table public.profiles
  drop constraint if exists profiles_phone_sane;
alter table public.profiles
  add constraint profiles_phone_sane
  check (
    phone is null
    or (phone ~ '^\+?[0-9]{6,20}$')
  );
