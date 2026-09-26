-- ============================================================
-- Pesan LOKASI (ala WhatsApp) — izinkan type='location'.
--
-- LATAR: fitur "kirim lokasi" di private chat & room menyimpan
-- koordinat sebagai JSON di kolom `text`
-- ({"lat":..,"lng":..,"label":".."}) dan menandai `type='location'`.
-- Constraint type yang ada BELUM memuat 'location' → insert ditolak
-- ("violates check constraint").
--
-- PERUBAHAN (hanya menambah satu nilai; nilai lama dipertahankan):
--   1) private_messages_type_check += 'location'
--   2) messages_type_check          += 'location'
--
-- Idempotent: drop if exists lalu add ulang (pola sama dengan
-- 20260814200000_private_messages_allow_coin_type.sql).
--
-- CARA APPLY: Management API (supabase db push HANG di Mac ini).
-- ============================================================

alter table public.private_messages
  drop constraint if exists private_messages_type_check;

alter table public.private_messages
  add constraint private_messages_type_check
  check (type in (
    'text', 'image', 'view_once', 'view_once_expired',
    'coin', 'gift', 'call', 'voice', 'video', 'location'
  ));

alter table public.messages
  drop constraint if exists messages_type_check;

alter table public.messages
  add constraint messages_type_check
  check (type in (
    'text', 'image', 'view_once', 'view_once_expired',
    'voice', 'gift', 'location'
  ));
