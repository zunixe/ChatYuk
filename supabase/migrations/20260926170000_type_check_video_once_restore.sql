-- ============================================================
-- PULIHKAN type video_once / video_once_expired yang HILANG.
--
-- INSIDEN: `20260926140000_messages_allow_location_type.sql` (fitur lokasi,
-- sesi paralel) men-DROP + ADD ulang kedua constraint type dan daftarnya
-- TIDAK memuat 'video_once'/'video_once_expired' (hanya 'video'). Karena
-- migrasi itu timestamp-nya LEBIH BARU dari milik video
-- (20260926130000/160000), constraint di DB live berakhir TANPA kedua type
-- itu → insert video sekali-lihat ditolak diam-diam.
--
-- PELAJARAN (pola regresi-urutan yang sudah didokumentasikan repo ini):
-- setiap migrasi yang men-DROP+ADD constraint type WAJIB memuat UNION
-- SEMUA type yang berlaku, atau migrasi yang lebih baru akan menghapusnya.
--
-- PERBAIKAN: satu sumber kebenaran = daftar UNION lengkap untuk KEDUA tabel,
-- ditulis dengan timestamp paling akhir.
--
-- CARA APPLY: Management API (supabase db push HANG di Mac ini).
-- ============================================================

-- ── private_messages: UNION lengkap ──
alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check
  check (type = any (array[
    'text'::text, 'image'::text, 'view_once'::text, 'view_once_expired'::text,
    'coin'::text, 'gift'::text, 'call'::text, 'voice'::text,
    'video'::text, 'video_once'::text, 'video_once_expired'::text,
    'location'::text
  ]));

-- ── messages (room): UNION lengkap ──
alter table public.messages
  drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check
  check (type = any (array[
    'text'::text, 'image'::text, 'view_once'::text, 'view_once_expired'::text,
    'voice'::text, 'coin'::text, 'gift'::text, 'call'::text,
    'video'::text, 'video_once'::text, 'video_once_expired'::text,
    'location'::text
  ]));
