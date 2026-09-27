-- ============================================================
-- Outbox Fase B: aktivasi cron worker (menguras public.outbox)
--
-- Latar: tabel outbox sudah ada (20260901020000) + edge function
-- `outbox-worker` sudah ter-deploy (ACTIVE v1). Tanpa cron, outbox tidak
-- pernah dikuras → notif yang ditulis via outbox TIDAK terkirim.
--
-- Cron ini memanggil edge function `outbox-worker` tiap 1 menit via
-- net.http_post (dengan x-app-secret). pg_cron resolusi minimum = 1 menit;
-- worker memproses batch 200 → throughput cukup.
--
-- Aman: saat outbox kosong, worker no-op ({"processed":0}) — nol dampak.
-- Tidak menyentuh fungsi FROZEN.
--
-- ROLLBACK: select cron.unschedule('chatyuk-outbox-worker');
-- ============================================================

select cron.unschedule('chatyuk-outbox-worker')
where exists (select 1 from cron.job where jobname = 'chatyuk-outbox-worker');

select cron.schedule(
  'chatyuk-outbox-worker',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/outbox-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-app-secret', (select app_shared_secret from public.app_settings where id = 'global')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

-- Verifikasi:
--   select jobname, schedule, active from cron.job where jobname='chatyuk-outbox-worker';
--   → 1 baris, active=true.
