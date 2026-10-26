-- NEGARA ASAL otomatis untuk user BARU + backfill.
--
-- Masalah: `home_country` hanya diisi sekali oleh migrasi sebelumnya. User
-- yang mendaftar SETELAH itu punya `home_country = NULL`, dan
-- `can_send_room_media` MELEWATI cek izin lintas negara bila home_country
-- kosong → user baru bisa kirim media di room publik NEGARA MANA PUN.
--
-- Perbaikan: trigger BEFORE INSERT mengisi home_country dari `country`
-- (negara saat registrasi). `home_country` tetap STABIL setelahnya — hanya
-- berubah lewat RPC `set_home_country` (maks 1x/30 hari).
--
-- SAFE: 1 fungsi trigger + 1 trigger pada `profiles` (BEFORE INSERT, hanya
--       mengisi kolom yang masih NULL) + backfill idempoten.
--       Tidak mengubah policy/RLS maupun kolom lain.
--       Fitur terdampak: registrasi (kolom tambahan terisi otomatis).

create or replace function public.set_home_country_default()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.home_country is null and coalesce(new.country, '') <> '' then
    new.home_country := new.country;
  end if;
  return new;
end;
$function$;

drop trigger if exists set_home_country_default_trg on public.profiles;
create trigger set_home_country_default_trg
  before insert on public.profiles
  for each row execute function public.set_home_country_default();

-- Backfill sisa (idempoten).
update public.profiles
   set home_country = country
 where home_country is null
   and coalesce(country, '') <> '';
