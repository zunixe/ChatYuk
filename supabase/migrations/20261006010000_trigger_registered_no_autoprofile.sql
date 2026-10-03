-- ============================================================
-- HENTIKAN pembuatan profil otomatis. SEMUA user (anon MAUPUN registered)
-- wajib mengisi nickname sendiri lewat layar isi-nama.
--
-- KEPUTUSAN USER (2026-10-05): "semua ga boleh bikin akun otomatis."
--
-- LATAR: trigger `handle_new_user_profile` (on_auth_user_created) membuat
-- baris profil untuk SETIAP auth.users → muncul nickname placeholder
-- 'PenggunaXXXXXX' (registered) / 'AnonXXXXXXXX' (anon) tanpa user memilih
-- nama. DILARANG.
--
-- PERUBAHAN:
--   1. Trigger TIDAK membuat profil untuk siapa pun (langsung return new).
--      Baris profil dibuat HANYA oleh `registerProfile` (client) SETELAH user
--      mengisi nickname. Gate root (`decideGateScreen`) memaksa EntryScreen
--      saat `!hasProfile` → user tetap diarahkan isi nama.
--   2. `_anon_write_ok()` diperluas: user yang PUNYA EMAIL di auth
--      (registered/Google) boleh menulis profilnya sendiri. Tanpa ini,
--      user registered baru TIDAK bisa INSERT profilnya (chicken-and-egg:
--      `_anon_write_ok` lama menolak karena baris profiles belum ada →
--      `is_registered` belum true). Lihat profiles_insert_own /
--      profiles_update_own yang memakai fungsi ini.
--
-- Tidak FROZEN. Idempotent.
-- ============================================================

-- ── 1. Trigger: jangan buat profil otomatis (semua user) ──
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  -- SEMUA user (anon & registered) WAJIB isi nickname sendiri.
  -- Tidak ada baris profil yang dibuat otomatis di sini.
  return new;
end;
$fn$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user_profile();

revoke execute on function public.handle_new_user_profile()
  from public, anon, authenticated;

-- ── 2. _anon_write_ok(): user ber-email (registered) boleh tulis profilnya ──
create or replace function public._anon_write_ok()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    not coalesce(
      (select require_registration from public.app_settings where id = 'global'),
      false)
  or auth.uid() in (select du from public.admin_dummy_uids() du)
  or coalesce(auth.email(), '') = 'zunixe@gmail.com'
  -- User punya email di auth (registered/Google/OTP) → boleh menulis
  -- profilnya sendiri (dibuat saat isi nama via registerProfile).
  or coalesce(auth.email(), '') <> ''
  or coalesce((select is_registered from public.profiles where id = auth.uid()), false),
  false)
$function$;

revoke execute on function public._anon_write_ok() from public, anon;
grant execute on function public._anon_write_ok() to authenticated, service_role;

-- Verifikasi setelah apply:
--   1) Trigger terpasang (tapi no-op):
--      select tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid
--       where c.relname='users' and not t.tgisinternal;   -- on_auth_user_created
--   2) User registered baru (Google) → TIDAK ada baris profiles sampai isi nama.
--   3) User anon baru → TIDAK ada baris profiles sampai isi nama.
--   4) Saat isi nama (registerProfile) → INSERT profil BERHASIL (email ada).
