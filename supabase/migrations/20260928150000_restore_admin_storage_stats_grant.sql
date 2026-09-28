-- Restore EXECUTE admin_storage_stats untuk aplikasi admin.
--
-- Konteks: 20260928120000 mencabut EXECUTE dari authenticated (disisa
-- service_role saja) → panel admin yang login via JWT (role authenticated)
-- kena 403 di kartu "Penggunaan Data Supabase" (loading/error terus).
-- Fungsi ini punya guard admin internal (hanya zunixe@gmail.com /
-- service_role yang lolos; user lain kena 'Unauthorized'), dan preseden
-- admin_table_sizes memang di-grant ke authenticated — jadi aman dikembalikan.
grant execute on function public.admin_storage_stats() to authenticated; -- SAFE: guard email admin internal di body fungsi (non-admin tetap ditolak); preseden admin_table_sizes juga granted ke authenticated; tanpa ini kartu storage admin 403
