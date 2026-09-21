-- ============================================================
-- FIX: trigger `social_guard_friend_requests` SELALU gagal 42703.
--
-- `_social_registered_guard()` ditulis untuk tabel `follows`
-- (new.follower_id / new.followee_id), tapi trigger yang sama juga
-- dipasang di `friend_requests` (kolomnya from_id / to_id):
--   169: create trigger social_guard_friend_requests ... on public.friend_requests
-- Akibatnya SETIAP INSERT/UPDATE friend_requests error
--   'record "new" has no field "follower_id"' (42703).
--
-- Dampak nyata (terverifikasi di live 2026-09-21):
--   · send_friend_request()  → selalu gagal
--   · respond_friend_request() → selalu gagal
--   · _are_friends()         → selalu false (butuh baris 'accepted')
--     → visibility privacy 'friends' mati, privacy_friends() kosong
--       sehingga picker "Teman kecuali" selalu empty.
--
-- Fix: guard membaca kolom sesuai TG_TABLE_NAME.
-- Bukan fungsi FROZEN (tidak ada di scripts/frozen_functions.txt).
-- ============================================================

create or replace function public._social_registered_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_a uuid;
  v_b uuid;
begin
  if tg_table_name = 'friend_requests' then
    v_a := new.from_id;
    v_b := new.to_id;
  else
    v_a := new.follower_id;
    v_b := new.followee_id;
  end if;

  if exists (
    select 1 from public.profiles p
    where p.id in (v_a, v_b)
      and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
  end if;
  return new;
end;
$fn$;
