-- ============================================================
-- Retensi user_location_history: buang riwayat lokasi > 90 hari.
--
-- Latar: tabel tumbuh tiap update lokasi user (update_my_location insert
-- baris baru). Tanpa retensi, di jutaan user tabel membengkak tanpa batas.
-- Data ini hanya dibaca fitur admin (admin_get_location_history & user detail)
-- untuk riwayat JANGKA PENDEK → 90 hari cukup.
--
-- Fungsi purge + cron harian 04:10 (di luar jam sibuk).
-- Aman: saat ini semua baris < 30 hari → nol baris terhapus (zero-impact).
-- Tidak menyentuh fungsi FROZEN.
--
-- ROLLBACK: select cron.unschedule('purge-location-history-90d');
--           drop function public.purge_location_history_90d();
-- ============================================================

create or replace function public.purge_location_history_90d()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_deleted integer;
begin
  delete from public.user_location_history
  where created_at < now() - interval '90 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function public.purge_location_history_90d() from public, anon, authenticated; -- SAFE: fungsi maintenance internal (hanya cron/service_role); tidak dipanggil klien user.

select cron.unschedule('purge-location-history-90d')
where exists (select 1 from cron.job where jobname = 'purge-location-history-90d');

select cron.schedule(
  'purge-location-history-90d',
  '10 4 * * *',
  $$select public.purge_location_history_90d()$$
);

-- Verifikasi:
--   select proname from pg_proc where proname='purge_location_history_90d';
--   select jobname, schedule, active from cron.job where jobname='purge-location-history-90d';
--   select public.purge_location_history_90d();  -- 0 (belum ada data >90 hari)
