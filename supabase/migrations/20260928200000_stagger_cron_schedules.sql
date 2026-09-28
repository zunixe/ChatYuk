-- ============================================================
-- STABILITAS pg_cron: konsolidasi 5 job per-menit → 1 job.
--
-- MASALAH (terukur 2026-09-28):
--   Instance Micro → `max_worker_processes = 6`, dipakai bersama oleh
--   realtime (2 walsender), pg_net worker, autovacuum (3), pg_cron launcher.
--   Tiap job pg_cron butuh 1 worker. Ada 5 job `* * * * *` TERPISAH +
--   4 job `*/5` yang menabrak di menit kelipatan 5.
--   Bukti: 414/8956 run gagal (4.6%) / 24 jam; di menit :15 pernah 11 job
--   gagal serentak dengan pesan "job startup timeout".
--
-- SOLUSI: gabung 5 job per-menit jadi SATU job `chatyuk-housekeeping`
--   (`housekeeping_tick()`) yang memanggil keempat fungsi housekeeping
--   berurutan → 1 worker, bukan 5. Tiap fungsi sudah menelan exception
--   sendiri (tidak melempar) sehingga satu error tidak menghentikan sisanya.
--
--   Job `chatyuk-outbox-worker` DIBIARKAN terpisah: ia memanggil edge
--   function via net.http_post (timeout 30s). Kalau digabung, worker
--   housekeeping bisa tertahan lama → dikembalikan ke menit `*/2` supaya
--   notif tetap cepat tanpa ikut menumpuk tiap menit.
--
--   Job `*/5` yang tidak dites dikunci jadwalnya dipindah menitnya supaya
--   tidak bertemu job per-menit di menit :00/:05.
--   CATATAN: `chatyuk-call-sweep` WAJIB tetap `*/5 * * * *` (dikunci
--   `supabase/tests/call_test.sql`) — tidak diubah.
--
-- Menambah/mengubah jadwal ini tidak menyentuh fungsi FROZEN —
-- `housekeeping_tick` adalah fungsi BARU (wrapper).
--
-- ROLLBACK: /tmp/chatyuk_cron_backup/jobs_before.json menyimpan definisi
--   awal; untuk mundur: `select cron.unschedule('chatyuk-housekeeping')`
--   lalu daftarkan ulang job lama via `cron.schedule(...)`.
--
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md).
-- ============================================================

-- 1) Wrapper housekeeping — panggil berurutan, abaikan error per bagian.
create or replace function public.housekeeping_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_idle   int := -1;
  v_voice  int := -1;
begin
  begin
    v_idle := public.presence_idle_tick();
  exception when others then null;
  end;
  begin
    v_voice := public.room_voice_sweep();
  exception when others then null;
  end;
  -- Bersihkan sinyal/broadcaster room yang basi (dulu 2 job DELETE terpisah).
  begin
    delete from public.room_signals
     where created_at < now() - interval '2 minutes';
  exception when others then null;
  end;
  begin
    delete from public.room_broadcasters
     where started_at < now() - interval '2 minutes';
    update public.rooms r
       set live_uid = null, live_started_at = null
     where r.live_uid is not null
       and not exists (
         select 1 from public.room_broadcasters rb
         where rb.room_id = r.id and rb.user_id = r.live_uid
       );
  exception when others then null;
  end;
  return jsonb_build_object('presence_idle', v_idle, 'voice_sweep', v_voice);
end;
$function$;

-- 2) Daftarkan job gabungan tiap menit (idempoten).
select cron.unschedule('chatyuk-housekeeping')
where exists (select 1 from cron.job where jobname = 'chatyuk-housekeeping');

select cron.schedule(
  'chatyuk-housekeeping',
  '* * * * *',
  $$ select public.housekeeping_tick(); $$
);

-- 3) Lepas 4 job per-menit yang kini tercakup housekeeping_tick.
--    (Presence & voice sweep + 2 cleanup room.)
select cron.unschedule('cleanup-room-signals')
where exists (select 1 from cron.job where jobname = 'cleanup-room-signals');

select cron.unschedule('cleanup-stale-broadcasters')
where exists (select 1 from cron.job where jobname = 'cleanup-stale-broadcasters');

select cron.unschedule('chatyuk-presence-idle')
where exists (select 1 from cron.job where jobname = 'chatyuk-presence-idle');

select cron.unschedule('sweep_room_voice')
where exists (select 1 from cron.job where jobname = 'sweep_room_voice');

-- 4) outbox-worker: turunkan frekuensi ke */2 (masih cepat, beban separuh).
select cron.alter_job(27, schedule := '*/2 * * * *');

-- 5) Sebar job */5 yang tidak dikunci test ke menit berbeda.
--    (chatyuk-call-sweep TIDAK disentuh — dikunci call_test.sql.)
select cron.alter_job(9,  schedule := '1-59/5 * * * *');  -- dummy-heartbeat
select cron.alter_job(14, schedule := '2-59/5 * * * *');  -- chatyuk-ai-presence
select cron.alter_job(20, schedule := '3-59/5 * * * *');  -- chatyuk-ai-claim-recovery

-- Verifikasi:
--   select jobid, schedule, jobname from cron.job
--    where jobname in ('chatyuk-housekeeping','chatyuk-outbox-worker',
--                      'dummy-heartbeat','chatyuk-ai-presence',
--                      'chatyuk-ai-claim-recovery','chatyuk-call-sweep')
--    order by jobid;
