-- ============================================================
-- ROLLBACK trigger pencegah hantu (20261004030000).
--
-- ALASAN (user, 2026-10-04):
--   Trigger `on_auth_user_created` membuat baris `profiles` untuk SETIAP
--   user baru (termasuk anon) saat `signInAnonymously`. Akibatnya gate
--   (`decideGateScreen`: `!hasProfile && isAnonymous → entry`) melihat
--   `hasProfile=true` untuk user anon baru → user anon LANGSUNG masuk app
--   ("login anon otomatis") TANPA layar isi nickname. Perilaku ini tidak
--   diinginkan.
--
-- KEPUTUSAN: batalkan trigger. Masalah "user hantu" (auth.users tanpa
--   profiles) ditangani lewat:
--     - `purge_ghost_users(24, false)` — cron harian 05:10 (jobid 33),
--       hapus HANYA hantu yang terbukti kosong & cukup umur.
--     - `cleanup_stale_anonymous` versi fail-safe (20261002000000).
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user_profile();

-- Verifikasi setelah apply:
--   select tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid
--    where c.relname='users' and not t.tgisinternal;   -- harus kosong
--   select proname from pg_proc where proname='handle_new_user_profile';
--                                                     -- harus kosong
