-- ============================================================
-- Penjaga: user dengan nickname PLACEHOLDER 'AnonXXXXXXXX' (generated
-- trigger handle_new_user_profile) WAJIB tetap `needs_onboarding = true`.
--
-- LATAR (2026-10-05): user yang register (email/OTP) lalu menutup app
--   sebelum memilih nama → nickname placeholder 'AnonXXXX' tertinggal, dan
--   (karena perluasan gate root) harus dipaksa ke EntryScreen. Tapi kalau
--   ada jalur lain men-set `needs_onboarding = false` tanpa mengganti
--   nickname, gate akan meloloskan mereka → berkeliaran sebagai 'AnonXXXX'.
--
-- GUARD ini menutup celah itu di level DB: pada INSERT/UPDATE profiles, bila
--   nickname cocok pola placeholder (^Anon[0-9A-F]{8}([0-9]+)?$) MAKA
--   `needs_onboarding` dipaksa true. Begitu user mengganti nama asli,
--   trigger tidak campur tangan (flag dibiarkan apa adanya).
--
-- PLUS backfill sekali jalan: tandai semua baris yang masih placeholder.
--
-- CARA APPLY: Management API.
-- ============================================================

create or replace function public.enforce_onboarding_placeholder()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  -- Pola: 'Anon' + 8 hex (id, uppercase) + opsional angka retry (1-5).
  if new.nickname ~ '^Anon[0-9A-F]{8}[0-9]*$' then
    new.needs_onboarding := true;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_enforce_onboarding_placeholder on public.profiles;
create trigger trg_enforce_onboarding_placeholder
  before insert or update of nickname, needs_onboarding on public.profiles
  for each row
  execute function public.enforce_onboarding_placeholder();

-- Backfill sekali jalan: pastikan semua placeholder tertandai onboarding.
update public.profiles
   set needs_onboarding = true
 where nickname ~ '^Anon[0-9A-F]{8}[0-9]*$'
   and needs_onboarding = false;

-- Verifikasi setelah apply:
--   select count(*) from public.profiles
--    where nickname ~ '^Anon[0-9A-F]{8}[0-9]*$' and needs_onboarding = false;  -- 0
