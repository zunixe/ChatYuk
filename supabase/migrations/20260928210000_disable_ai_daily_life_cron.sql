-- ============================================================
-- Nonaktifkan cron `chatyuk-ai-daily-life` (belum dipakai).
--
-- Job ini menjalankan edge function `ai-daily-life` tiap hari 22:00
-- (generate story harian untuk akun dummy `kind='regular'`). Fitur belum
-- dipakai → dimatikan supaya tidak menambah beban/worker cron.
--
-- Pilihan: `cron.unschedule` (hapus total, mudah dipulihkan dari
-- `20260912010000_audit_cleanup_batch.sql`) — bukan set active=false,
-- supaya benar-benar bebas dari scheduler.
--
-- TIDAK menyentuh fungsi FROZEN, GRANT, RLS, atau DDL tabel.
-- Tidak ada test yang mengunci job ini.
--
-- ROLLBACK / AKTIFKAN LAGI:
--   jalankan ulang blok `cron.schedule('chatyuk-ai-daily-life', '0 22 * * *', ...)`
--   dari `supabase/migrations/20260912010000_audit_cleanup_batch.sql`.
--
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md).
-- ============================================================

select cron.unschedule('chatyuk-ai-daily-life')
where exists (
  select 1 from cron.job where jobname = 'chatyuk-ai-daily-life'
);

-- Verifikasi (harus 0 baris):
--   select jobid, jobname from cron.job where jobname = 'chatyuk-ai-daily-life';
