-- ============================================================
-- RESTORE EXECUTE untuk fungsi admin yang dipanggil APP tapi terlanjur
-- dicabut oleh hardening 20260928120000 / 20260928140000.
--
-- INSIDEN (2026-09-28, lanjutan pola admin_dummy_uids):
--   `revoke execute ... from public, anon, authenticated` menyapu fungsi
--   admin yang MASIH DIPANGGIL app admin dari perangkat admin:
--     - admin_sweep_calls          (admin_chats.dart → sweep zombie call)
--     - admin_registrations_daily  (chart Ringkasan)
--     - admin_contact_messages_page / admin_contact_set_read / admin_contact_delete
--     - admin_set_privacy_bypass
--   Gejala: log Postgres `42501 permission denied for function
--   admin_sweep_calls / admin_registrations_daily`; chart & kontak admin rusak.
--
-- KENAPA AMAN dikembalikan ke `authenticated`:
--   KEENAM fungsi sudah punya guard internal
--     `if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise ...`.
--   Jadi non-admin yang mencoba tetap ditolak di dalam fungsi — EXECUTE
--   bukan media bypass, hanya pintu masuk ke guard itu.
--   (Preseden sah: `admin_storage_stats` juga authenticated=true + guard sama.)
--
-- YANG TIDAK DIPULIHKAN (sengaja tetap dicabut): fungsi internal/trigger
-- murni yang benar-benar tidak dipanggil klien — lihat migrasi revoke.
--
-- Bukan fungsi FROZEN (hanya GRANT, body tidak disentuh).
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md).
-- ROLLBACK: jalankan revoke di 20260928120000/20260928140000 untuk 6 fn ini.
-- ============================================================

-- SAFE: grant execute fungsi admin ber-guard zunixe@gmail.com (bukan REVOKE);
-- hanya membuka pintu ke guard internal. Fitur: monitor chat admin (sweep call,
-- chart registrasi, tab kontak, privacy bypass). anon tetap DILARANG.
grant execute on function public.admin_sweep_calls() to authenticated;
grant execute on function public.admin_registrations_daily(integer, integer) to authenticated;
grant execute on function public.admin_contact_messages_page(integer, integer) to authenticated;
grant execute on function public.admin_contact_set_read(uuid, boolean) to authenticated;
grant execute on function public.admin_contact_delete(uuid) to authenticated;
grant execute on function public.admin_set_privacy_bypass(boolean) to authenticated;

-- Verifikasi (harus true semua untuk authenticated):
--   select p.proname, has_function_privilege('authenticated', p.oid,'EXECUTE')
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and p.proname in (
--     'admin_sweep_calls','admin_registrations_daily','admin_contact_messages_page',
--     'admin_contact_set_read','admin_contact_delete','admin_set_privacy_bypass');
