-- ============================================================
-- Fix: "user online terus" akibat clock skew HP (last_seen di MASA DEPAN).
--
-- Gejala: user (mis. sitirahmawAti) selalu tampil ONLINE walau sudah lama
-- tidak aktif. Akar: client menulis `last_seen = DateTime.now()` memakai
-- JAM HP; bila jam HP MAJU (~1-2 jam), timestamp tersimpan di masa depan.
-- get_online_users & presence_for memfilter `last_seen >= now() - 30min`
-- → timestamp masa depan SELALU lolos → selamanya online.
--
-- Fix server-side (menetralkan SEMUA jalur/client apa pun):
--   1) TRIGGER clamp: `last_seen` tidak boleh > now() (server clock).
--   2) Bersihkan baris yang sudah rusak (last_seen di masa depan).
-- ============================================================

-- (1) Fungsi clamp: paksa last_seen <= now() saat INSERT/UPDATE.
create or replace function public.clamp_last_seen()
returns trigger
language plpgsql
as $$
begin
  if new.last_seen is not null and new.last_seen > now() then
    new.last_seen := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_clamp_last_seen on public.profiles;
create trigger trg_clamp_last_seen
  before insert or update of last_seen on public.profiles
  for each row execute function public.clamp_last_seen();

-- (2) Bersihkan data lama yang terlanjur di masa depan.
update public.profiles
   set last_seen = now()
 where last_seen > now();

-- (3) Jaring pengaman di query online: selain clamp, get_online_users juga
--     sudah memfilter last_seen >= now() - 30min. Dengan clamp di atas,
--     user yang jam HP-nya maju kini akan "basi" normal & jadi offline.
