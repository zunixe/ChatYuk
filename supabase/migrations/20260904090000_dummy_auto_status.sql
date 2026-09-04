-- ============================================================
-- Status akun dummy PERSISTEN sesuai yang di-set admin:
--   "online" → online SELAMANYA (heartbeat refresh last_seen tiap 5
--              menit — filter daftar online memakai last_seen < 30 menit,
--              tanpa heartbeat dummy akan hilang dari daftar)
--   "idle"   → idle SELAMANYA (heartbeat juga)
--   "offline"→ offline SELAMANYA (tidak disentuh)
-- Dulu: dummy yang di-set online menghilang dari daftar setelah 30 menit
-- (tidak ada device yang kirim heartbeat) / jadi offline sendiri.
-- ============================================================

-- 1. Hapus pendekatan lama (auto-transition) bila pernah di-apply.
select cron.unschedule('dummy-auto-status')
where exists (select 1 from cron.job where jobname = 'dummy-auto-status');
drop function if exists public.dummy_auto_status();

-- 2. Heartbeat dummy: last_seen selalu segar untuk dummy yang di-set
--    online/idle. Offline TIDAK disentuh.
create or replace function public.dummy_heartbeat()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare n int;
begin
  update public.profiles p
     set last_seen = now()
   where p.id in (select uid from public.dummy_accounts)
     and p.status in ('online', 'idle');
  get diagnostics n = row_count;
  return jsonb_build_object('refreshed', n);
end;
$fn$;

-- 3. Cron tiap 5 menit (interval < 30 menit cutoff daftar online).
select cron.schedule('dummy-heartbeat', '*/5 * * * *',
  $$select public.dummy_heartbeat()$$)
where not exists (select 1 from cron.job where jobname = 'dummy-heartbeat');
