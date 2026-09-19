-- Retensi & pembersihan call otomatis (TIDAK bergantung admin).
--
-- Latar: `admin_sweep_calls()` sudah ada dan benar (akhiri ringing basi,
-- akhiri answered tanpa heartbeat, hapus call_signals > 1 jam) — TAPI dulu
-- hanya terpanggil saat admin membuka panel. Akibatnya untuk user biasa:
-- call zombie menggantung dan call_signals menumpuk sampai admin kebetulan
-- membuka panel (terukur 2.160 kB untuk tabel yang hanya berisi 81 baris).
--
-- Migrasi ini HANYA menjadwalkan fungsi yang sudah ada — tidak mengubah
-- definisinya, tidak menyentuh fungsi FROZEN, tidak mengubah tabel/policy.
select cron.unschedule('chatyuk-call-sweep')
where exists (select 1 from cron.job where jobname = 'chatyuk-call-sweep');

select cron.schedule(
  'chatyuk-call-sweep',
  '*/5 * * * *',
  $$select public.admin_sweep_calls()$$
);
