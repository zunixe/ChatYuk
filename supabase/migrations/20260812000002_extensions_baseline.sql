-- Extension baseline: pg_cron dipakai migration berikutnya (purge, reengage,
-- dummy_auto_status). Di hosted Supabase sudah aktif default; di local
-- dibuat lewat SQL ini. Idempotent.
create extension if not exists pg_cron;
create extension if not exists pg_net;
