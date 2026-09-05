-- Fix: akun dummy gagal update profil dari sheet Edit Profil.
--
-- Akar masalah: dummy dibuat dari panel admin TANPA validasi panjang
-- nickname (admin_update_dummy_profile hanya validasi gender/umur).
-- Policy RLS profiles_update_own versi strict (wallet_ledger_phase1)
-- mensyaratkan length(trim(nickname)) >= 3 pada SETIAP update — termasuk
-- edit umur/kota (NEW.nickname = OLD.nickname). User biasa tidak pernah
-- punya nickname <3 (client validasi), jadi HANYA dummy kena: semua edit
-- profil dummy ditolak RLS (42501) → "gagal memperbaharui profil".
--
-- Fix 1: pastikan policy relaxed (sama dengan 20260829060000) aktif —
--        idempoten, aman walau sudah di-apply.
-- Fix 2: dummy_accounts.nickname ikut ter-sync saat dummy edit profil
--        sendiri (sebelumnya hanya profiles yang berubah → desync).
-- Fix 3: admin_update_dummy_profile validasi nickname 3-20 (server-side).

-- ── Fix 1 ──
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles
for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- ── Fix 2 ──
create or replace function public.sync_dummy_nickname()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update public.dummy_accounts
     set nickname = new.nickname
   where uid = new.id
     and nickname is distinct from new.nickname;
  return new;
end;
$fn$;

drop trigger if exists trg_sync_dummy_nickname on public.profiles;
create trigger trg_sync_dummy_nickname
  after update of nickname on public.profiles
  for each row execute function public.sync_dummy_nickname();

-- Backfill: samakan nickname dummy_accounts dengan profiles saat ini.
update public.dummy_accounts d
   set nickname = p.nickname
  from public.profiles p
 where p.id = d.uid
   and d.nickname is distinct from p.nickname;

-- ── Fix 3 ──
create or replace function public.admin_update_dummy_profile(
  p_uid uuid,
  p_nickname text,
  p_gender text,
  p_age int,
  p_country text,
  p_city text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_gender not in ('male', 'female') then
    raise exception 'Gender tidak valid';
  end if;
  if p_age < 18 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  if length(trim(p_nickname)) < 3 or length(p_nickname) > 20 then
    raise exception 'Nickname harus 3-20 karakter';
  end if;
  update public.profiles
  set nickname = p_nickname, gender = p_gender, age = p_age,
      country = p_country, city = p_city, last_seen = now()
  where id = p_uid;
  update public.dummy_accounts set nickname = p_nickname where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── Fix 4: create dummy — validasi nickname (panjang + duplikat) ──
-- Tanpa ini, nickname yang sudah dipakai (constraint unique profiles)
-- atau di luar 3-20 gagal DI TENGAH proses: user anonymous sudah
-- terlanjur dibuat di GoTrue tapi row profiles gagal insert → akun
-- yatim tanpa profil + toast "gagal" tanpa penjelasan.
create or replace function public.admin_register_dummy(
  p_uid uuid,
  p_nickname text,
  p_refresh_token text,
  p_gender text default 'male',
  p_age int default 25,
  p_country text default 'Indonesia',
  p_city text default 'Jakarta'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_gender not in ('male', 'female') then
    raise exception 'Gender tidak valid';
  end if;
  if p_age < 18 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  if length(trim(p_nickname)) < 3 or length(p_nickname) > 20 then
    raise exception 'Nickname harus 3-20 karakter';
  end if;
  if exists (select 1 from public.profiles where lower(nickname) = lower(trim(p_nickname))) then
    raise exception 'Nickname sudah dipakai';
  end if;
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered, last_seen)
  values (p_uid, p_nickname, p_gender, p_age, p_country, p_city, 'offline', true, now())
  on conflict (id) do update set
    nickname = excluded.nickname,
    gender = excluded.gender,
    age = excluded.age,
    country = excluded.country,
    city = excluded.city,
    last_seen = now();
  insert into public.dummy_accounts (uid, nickname, refresh_token)
  values (p_uid, p_nickname, p_refresh_token)
  on conflict (uid) do update set
    nickname = excluded.nickname,
    refresh_token = excluded.refresh_token;
  return jsonb_build_object('ok', true, 'uid', p_uid);
end;
$$;
