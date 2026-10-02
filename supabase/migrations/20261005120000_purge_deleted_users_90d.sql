-- ============================================================
-- Retensi arsip `deleted_users`: buang arsip > 90 hari.
--
-- LATAR (2026-10-05): semua user yang dihapus (self_delete / admin_delete /
--   stale_cleanup / nickname_claim / onboarding_placeholder) di-ARSIP ke
--   `public.deleted_users` oleh `fn_archive_deleted_user`. TIDAK ada
--   purge → tabel tumbuh selamanya (kini 1.815 baris & akan terus naik).
--   Arsip hanya untuk audit jangka pendek (lihat tab "Terhapus" admin).
--
-- FUNGSI: buang baris `deleted_at < now() - 90 hari`. Idempoten, aman
--   (nol baris terhapus selama data < 90 hari). + cron harian 04:30
--   (di luar jam sibuk, setelah cleanup anon 04:00).
--
-- ROLLBACK: select cron.unschedule('purge-deleted-users-90d');
--           drop function public.purge_deleted_users_90d();
-- ============================================================

create or replace function public.purge_deleted_users_90d()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_deleted integer;
begin
  delete from public.deleted_users
  where deleted_at < now() - interval '90 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function public.purge_deleted_users_90d() from public, anon, authenticated; -- SAFE: fungsi maintenance internal (hanya cron/service_role); tidak dipanggil klien user.

select cron.unschedule('purge-deleted-users-90d')
where exists (select 1 from cron.job where jobname = 'purge-deleted-users-90d');

select cron.schedule(
  'purge-deleted-users-90d',
  '30 4 * * *',
  $$select public.purge_deleted_users_90d()$$
);

-- Verifikasi setelah apply:
--   select jobid, jobname, schedule from cron.job where jobname='purge-deleted-users-90d';
--   select public.purge_deleted_users_90d();   -- jalankan manual (aman)
