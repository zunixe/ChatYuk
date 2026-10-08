-- ============================================================
-- Verifikasi Nomor HP via Telegram + badge emas.
--
-- Fitur: user mengisi nomor HP (kolom `profiles.phone` sudah ada). Untuk
-- mendapat badge terverifikasi, user membuka bot Telegram @chatyuk_verify_bot,
-- menekan tombol "Bagikan nomor", lalu bot mencocokkan nomor kontak dengan
-- nomor yang didaftarkan. Cocok → `profiles.phone_verified_at` diisi.
--
-- Dokumen lengkap: PHONE_VERIFY_TELEGRAM.md
--
-- PERUBAHAN:
--   1) profiles.phone_verified_at timestamptz  — penanda verified.
--   2) tabel phone_verifications               — sesi verifikasi (token).
--   3) trigger reset verified saat nomor ganti.
--   4) RPC: phone_verify_start / phone_verify_status / phone_verify_confirm /
--      verified_uids.
--
-- PENTING: RPC `verified_uids` dipakai app untuk badge user lain TANPA
-- menyentuh get_online_users/nearby_users (hindari regresi fungsi luas).
--
-- Idempotent. Tidak menyentuh fungsi FROZEN. CARA APPLY: supabase db push /
-- Management API.
-- ============================================================

-- ── 1. Kolom penanda verified ──
alter table public.profiles
  add column if not exists phone_verified_at timestamptz;

-- ── 2. Tabel sesi verifikasi ──
create table if not exists public.phone_verifications (
  id bigserial primary key,
  uid uuid not null references public.profiles(id) on delete cascade,
  phone text not null,
  token text not null unique,
  telegram_chat_id bigint,
  status text not null default 'pending'
    check (status in ('pending','verified','expired','failed')),
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  verified_at timestamptz
);

create index if not exists phone_verifications_uid_idx
  on public.phone_verifications(uid);
create index if not exists phone_verifications_token_idx
  on public.phone_verifications(token);
create index if not exists phone_verifications_uid_created_idx
  on public.phone_verifications(uid, created_at desc);

alter table public.phone_verifications enable row level security;

-- Hanya pemilik baris yang boleh membaca. Tulis HANYA lewat RPC (SECURITY
-- DEFINER), jadi tidak ada policy insert/update untuk user biasa.
drop policy if exists phone_verifications_select_own on public.phone_verifications; -- SAFE: tabel BARU (phone_verifications), tak menyentuh tabel lama
create policy phone_verifications_select_own -- SAFE: policy SELECT tabel baru, tanpa akses anon
  on public.phone_verifications
  for select
  to authenticated
  using (uid = auth.uid());

-- ── 3. Trigger: nomor berubah → reset verified ──
create or replace function public.reset_phone_verified_on_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Nomor diganti (beda digit ternormalisasi) → badge dicabut sampai
  -- verifikasi ulang. Perbandingan pakai digit saja supaya '+62 812' dan
  -- '+62812' dianggap sama.
  if regexp_replace(coalesce(new.phone,''), '[^0-9]', '', 'g')
     is distinct from
     regexp_replace(coalesce(old.phone,''), '[^0-9]', '', 'g')
  then
    new.phone_verified_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reset_phone_verified on public.profiles;
create trigger trg_reset_phone_verified
  before update of phone on public.profiles
  for each row execute function public.reset_phone_verified_on_change();

-- ── 4. RPC: mulai verifikasi ──
-- Dipanggil app (authenticated). Membuat token sekali-pakai; rate limit
-- 3 percobaan per jam; token berlaku 15 menit.
create or replace function public.phone_verify_start()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_recent int;
  v_token text;
  v_expires timestamptz := now() + interval '15 minutes';
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select phone into v_phone from public.profiles where id = v_uid;
  if v_phone is null or v_phone = '' then
    raise exception 'phone_empty';
  end if;

  -- Rate limit: maksimal 3 permintaan dalam 1 jam terakhir.
  select count(*) into v_recent
  from public.phone_verifications
  where uid = v_uid and created_at > now() - interval '1 hour';
  if v_recent >= 3 then
    raise exception 'rate_limited';
  end if;

  -- Batalkan token pending lama (satu sesi aktif per user).
  update public.phone_verifications
     set status = 'expired'
   where uid = v_uid and status = 'pending';

  v_token := encode(extensions.gen_random_bytes(16), 'hex');

  insert into public.phone_verifications(uid, phone, token, status, expires_at)
  values (v_uid, v_phone, v_token, 'pending', v_expires);

  return jsonb_build_object(
    'token', v_token,
    'phone', v_phone,
    'expires_at', v_expires
  );
end;
$$;

-- ── 5. RPC: status verifikasi diri sendiri ──
create or replace function public.phone_verify_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_verified timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select phone, phone_verified_at into v_phone, v_verified
  from public.profiles where id = v_uid;
  return jsonb_build_object(
    'phone', coalesce(v_phone, ''),
    'verified', v_verified is not null,
    'verified_at', v_verified
  );
end;
$$;

-- ── 6. RPC: konfirmasi (dipanggil webhook Telegram, service_role) ──
-- Membandingkan nomor kontak dengan nomor pendaftaran (digit saja). Bila
-- cocok → tandai verified + set profiles.phone_verified_at.
create or replace function public.phone_verify_confirm(
  p_token text,
  p_phone text,
  p_chat_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.phone_verifications%rowtype;
  v_want text;
  v_got text;
begin
  select * into v_row
  from public.phone_verifications
  where token = p_token
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'unknown_token');
  end if;
  if v_row.status = 'verified' then
    return jsonb_build_object('ok', true, 'reason', 'already_verified');
  end if;
  if v_row.expires_at < now() then
    update public.phone_verifications
       set status = 'expired' where id = v_row.id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- Normalisasi: bandingkan digit saja.
  v_want := regexp_replace(coalesce(v_row.phone, ''), '[^0-9]', '', 'g');
  v_got := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');

  -- Bandingkan juga versi tanpa kode negara '0' vs '62' (umum di ID) agar
  -- tidak gagal karena format +62/0. Cocok kalau salah satu suffix 9+ digit
  -- sama.
  if v_want <> v_got then
    if length(v_want) >= 9 and length(v_got) >= 9
       and right(v_want, 9) = right(v_got, 9) then
      -- anggap cocok (suffix sama)
      null;
    else
      update public.phone_verifications
         set attempts = attempts + 1, status = 'failed'
       where id = v_row.id;
      return jsonb_build_object('ok', false, 'reason', 'phone_mismatch');
    end if;
  end if;

  update public.phone_verifications
     set status = 'verified',
         verified_at = now(),
         telegram_chat_id = coalesce(p_chat_id, telegram_chat_id)
   where id = v_row.id;

  update public.profiles
     set phone_verified_at = now()
   where id = v_row.uid;

  return jsonb_build_object('ok', true, 'reason', 'verified', 'uid', v_row.uid);
end;
$$;

-- ── 7. RPC: daftar uid terverifikasi (untuk badge user lain) ──
create or replace function public.verified_uids(p_uids uuid[])
returns uuid[]
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
  from public.profiles p
  where p.id = any(p_uids)
    and p.phone_verified_at is not null;
$$;

-- ── 8. Hak akses ──
-- Client authenticated: start/status/verified_uids. Confirm hanya service_role
-- (dipanggil edge function webhook).
grant execute on function public.phone_verify_start() to authenticated;
grant execute on function public.phone_verify_status() to authenticated;
grant execute on function public.verified_uids(uuid[]) to authenticated;
grant execute on function public.phone_verify_confirm(text, text, bigint) to service_role;
