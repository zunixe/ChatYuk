-- ============================================================
-- FIX: nickname duplikat beda kapitalisasi (case-sensitive UNIQUE).
--
-- LATAR (diagnosis 2026-10-04):
--   `profiles_nickname_unique` = UNIQUE (nickname) bersifat
--   CASE-SENSITIVE, sehingga "Budi" dan "budi" boleh berdampingan.
--   Terbukti di produksi: 6 pasang nickname hanya beda kapitalisasi
--   ("Lukman"/"lukman", "Joy"/"joy", dst). Karena cek ketersediaan
--   (klien `.eq` + `claim_nickname` WHERE nickname = ...) juga
--   case-sensitive, user yang mengetik varian case berbeda melihat
--   "nickname sudah digunakan" secara membingungkan / atau malah
--   membuat duplikat ketiga.
--
-- PERBAIKAN (3 bagian):
--   1) Rename 6 baris duplikat agar case-insensitive unik.
--      Aturan: pertahankan yang `is_registered=true`; jika dua-duanya
--      terdaftar, pertahankan yang `created_at` paling tua.
--      Varian yang di-rename diberi suffix angka ("Budi" -> "Budi2").
--   2) Tambah unique index case-insensitive: UNIQUE (lower(nickname)).
--      Ini mencegah duplikat baru di level DB.
--   3) (Klien) isNicknameAvailable diubah case-insensitive + RPC
--      claim_nickname/match pakai lower(). Lihat perubahan Dart.
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

begin;

-- ── 1. Rename varian duplikat yang "kalah" ──────────────────────────
-- Hanya menyentuh baris dengan id eksplisit (aman, deterministik).
update public.profiles set nickname = 'Lukman2'
 where id = '38c550ee-c4eb-434c-b12c-b3d0afb4a59d';  -- "Lukman" (anon) → Lukman2
update public.profiles set nickname = 'Dedi2'
 where id = 'c2a459a6-91f1-48cd-92ed-53daef291c4b';  -- "Dedi"   (anon) → Dedi2
update public.profiles set nickname = 'joy2'
 where id = 'cc6bb724-1e6e-4b7d-996e-617fa924d8f6';  -- "joy"    (anon, lebih muda) → joy2
update public.profiles set nickname = 'toni2'
 where id = '49ab835f-af02-4aa5-984e-963c711b49dd';  -- "toni"   (registered, lebih muda) → toni2
update public.profiles set nickname = 'ARY2'
 where id = 'b4f96f02-d2f9-4686-ae3f-c2c9e8b34fe0';  -- "ARY"    (registered, lebih muda) → ARY2
update public.profiles set nickname = 'yudi2'
 where id = '0d61eb23-4d56-45b0-b699-9f23912118bb';  -- "yudi"   (registered, lebih muda) → yudi2

-- ── 2. Unique index case-insensitive ────────────────────────────────
-- Jaring supaya tidak ada lagi "Budi" vs "budi". Memakai lower(trim()).
-- drop index bila sudah ada (idempoten saat re-apply).
drop index if exists public.profiles_nickname_lower_unique;
create unique index profiles_nickname_lower_unique
  on public.profiles (lower(trim(nickname)));

commit;

-- Verifikasi setelah apply:
--   1) 0 duplikat case tersisa:
--      select lower(trim(nickname)), count(*) from profiles
--       group by 1 having count(*) > 1;   -- harus kosong
--   2) Index ada:
--      select indexname from pg_indexes
--       where tablename='profiles' and indexname like '%nickname_lower%';
