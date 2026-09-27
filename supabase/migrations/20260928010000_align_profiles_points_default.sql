-- ============================================================
-- Selaraskan drift: profiles.points DEFAULT 50 (samakan dengan PROD)
--
-- Latar: saat fresh-replay 334 migration, `profiles.points` berakhir dengan
-- default 0 (dari 20260812100500_profiles_columns_baseline.sql), karena
-- 20260814090000_points_v1_baseline.sql hanya `add column if not exists`
-- (tidak mengubah default pada kolom yang sudah ada).
--
-- Di PROD default-nya = 50 (dikonfirmasi via Management API). Akibat default
-- 0: trigger `profiles_ledger_signup_trg` menulis coin_ledger amount=0 →
-- melanggar check `coin_ledger_amount_check` → insert profiles GAGAL.
--
-- Migration ini menyamakan lokal dengan prod. Idempotent.
-- ============================================================

alter table public.profiles alter column points set default 50;
