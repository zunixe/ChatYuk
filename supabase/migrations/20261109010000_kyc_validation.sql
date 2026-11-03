-- ══════════════════════════════════════════════════════════════════════
-- KYC profesional (2026-11-09): validasi dokumen & orang di server.
--
-- Klien (kyc_screen) kini: kamera KTP + OCR + cek tajam/silau, selfie
-- liveness (kedip + toleh), NIK terisi dari KTP. Hasilnya dikirim sebagai
-- `checks` (untuk admin) — TETAPI klien bisa dimodifikasi, jadi server
-- memvalidasi ulang semua yang bisa divalidasi:
--  - hanya KTP (withdraw ke DANA = WNI);
--  - struktur NIK: 16 digit, kode provinsi resmi, kab/kec ≠ 00, tgl lahir
--    valid (perempuan +40), nomor urut ≠ 0000;
--  - tgl lahir input == tgl lahir di NIK; usia ≥ 17;
--  - SATU NIK = SATU akun (unique index pending/approved) → tutup celah
--    1 KTP dipakai banyak akun penerima withdraw;
--  - maks 3 pengajuan / 24 jam;
--  - error = KODE (KYC_*) → klien menampilkan string bilingual.
-- Admin:
--  - admin_kyc_list TIDAK lagi mengirim foto (dulu semua foto + riwayat
--    sekaligus = payload besar); foto lewat admin_kyc_photos(id).
--  - admin_kyc_review: kunci baris + wajib status pending (dulu bisa
--    menimpa keputusan admin lain / approve ulang yang ditolak).
-- ══════════════════════════════════════════════════════════════════════

alter table public.kyc_requests
  add column if not exists checks jsonb not null default '{}'::jsonb,
  add column if not exists server_checks jsonb not null default '{}'::jsonb;

create unique index if not exists kyc_requests_nik_active_uq
  on public.kyc_requests (id_number)
  where status in ('pending', 'approved');

-- ── Struktur NIK → (tgl lahir, perempuan). null = tidak valid. ──────────
create or replace function public.kyc_nik_info(p_nik text)
returns jsonb
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  prov int; d int; m int; yy int; y int; birth date; fem boolean;
begin
  if p_nik is null or p_nik !~ '^[0-9]{16}$' then return null; end if;
  prov := substr(p_nik, 1, 2)::int;
  if prov not in (11,12,13,14,15,16,17,18,19,21,31,32,33,34,35,36,
                  51,52,53,61,62,63,64,65,71,72,73,74,75,76,81,82,
                  91,92,93,94,95,96) then
    return null;
  end if;
  if substr(p_nik, 3, 2) = '00' or substr(p_nik, 5, 2) = '00'
     or substr(p_nik, 13, 4) = '0000' then
    return null;
  end if;
  d := substr(p_nik, 7, 2)::int;
  fem := d > 40;
  if fem then d := d - 40; end if;
  m := substr(p_nik, 9, 2)::int;
  yy := substr(p_nik, 11, 2)::int;
  y := case when yy > extract(year from now())::int % 100
            then 1900 + yy else 2000 + yy end;
  begin
    birth := make_date(y, m, d);
  exception when others then
    return null;
  end;
  if birth > current_date then return null; end if;
  return jsonb_build_object('birth_date', birth, 'female', fem);
end;
$function$;

revoke execute on function public.kyc_nik_info(text) from public, anon;

-- ── submit_kyc v2 (+ p_checks) ──────────────────────────────────────────
drop function if exists public.submit_kyc(text, text, text, text, text, date);

create or replace function public.submit_kyc(
  p_full_name text,
  p_id_type text,
  p_id_number text,
  p_id_photo text,
  p_selfie_photo text,
  p_birth_date date default null,
  p_checks jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  v_nik text := trim(coalesce(p_id_number, ''));
  v_info jsonb;
  v_gender text;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if coalesce(p_id_type, 'ktp') <> 'ktp' then
    raise exception 'KYC_DOC_TYPE';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 3 then
    raise exception 'KYC_NAME_INVALID';
  end if;
  if length(coalesce(p_id_photo, '')) < 100
     or length(coalesce(p_selfie_photo, '')) < 100 then
    raise exception 'KYC_PHOTOS_REQUIRED';
  end if;

  v_info := public.kyc_nik_info(v_nik);
  if v_info is null then raise exception 'KYC_NIK_INVALID'; end if;
  if p_birth_date is null
     or p_birth_date <> (v_info->>'birth_date')::date then
    raise exception 'KYC_BIRTH_MISMATCH';
  end if;
  if p_birth_date > (current_date - interval '17 years')::date then
    raise exception 'KYC_UNDERAGE';
  end if;

  -- Kunci per user → dua submit bersamaan tidak lolos cek di bawah.
  perform pg_advisory_xact_lock(hashtext('kyc:' || uid::text));

  if exists (select 1 from kyc_requests
             where user_id = uid and status in ('pending', 'approved')) then
    raise exception 'KYC_ALREADY_SUBMITTED';
  end if;
  if (select count(*) from kyc_requests
      where user_id = uid and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'KYC_TOO_MANY';
  end if;
  if exists (select 1 from kyc_requests
             where id_number = v_nik and user_id <> uid
               and status in ('pending', 'approved')) then
    raise exception 'KYC_NIK_USED';
  end if;

  select gender into v_gender from profiles where id = uid;

  begin
    insert into kyc_requests (user_id, status, full_name, id_type, id_number,
                              id_photo, selfie_photo, birth_date, checks,
                              server_checks)
    values (uid, 'pending', upper(trim(p_full_name)), 'ktp', v_nik,
            p_id_photo, p_selfie_photo, p_birth_date,
            coalesce(p_checks, '{}'::jsonb),
            jsonb_build_object(
              'nik_valid', true,
              'birth_match_nik', true,
              'nik_female', (v_info->>'female')::boolean,
              'gender_match_profile',
                case when v_gender in ('female', 'male')
                     then (v_info->>'female')::boolean = (v_gender = 'female')
                     end));
  exception when unique_violation then
    raise exception 'KYC_NIK_USED';
  end;

  return jsonb_build_object('ok', true, 'status', 'pending');
end;
$function$;

revoke execute on function public.submit_kyc(text, text, text, text, text, date, jsonb)
  from public, anon;
grant execute on function public.submit_kyc(text, text, text, text, text, date, jsonb)
  to authenticated;

-- ── Admin: daftar tanpa foto ────────────────────────────────────────────
create or replace function public.admin_kyc_list(p_status text default 'pending')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select k.id, k.user_id, k.status, k.full_name, k.id_type, k.id_number,
           k.birth_date, k.reject_reason, k.created_at, k.reviewed_at,
           k.checks, k.server_checks, p.nickname, p.email, p.gender
    from kyc_requests k
    join profiles p on p.id = k.user_id
    where (p_status = 'all' or k.status = p_status)
    limit 200
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$;

create or replace function public.admin_kyc_photos(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare r record;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;
  select id_photo, selfie_photo into r from kyc_requests where id = p_request_id;
  if not found then raise exception 'Request not found'; end if;
  return jsonb_build_object('id_photo', r.id_photo, 'selfie_photo', r.selfie_photo);
end; $function$;

revoke execute on function public.admin_kyc_photos(uuid) from public, anon;
grant execute on function public.admin_kyc_photos(uuid) to authenticated;

-- ── Admin: review aman (lock + wajib pending) ───────────────────────────
create or replace function public.admin_kyc_review(
  p_request_id uuid, p_approve boolean, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); v_status text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;

  select status into v_status from kyc_requests
   where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED',
                              'status', v_status);
  end if;
  if not p_approve and length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Reason required';
  end if;

  update kyc_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    reject_reason = case when p_approve then null else trim(p_reason) end,
    reviewed_by = uid,
    reviewed_at = now(),
    updated_at = now()
  where id = p_request_id;

  return jsonb_build_object('ok', true, 'approved', p_approve);
end; $function$;

revoke execute on function public.admin_kyc_list(text) from public, anon;
revoke execute on function public.admin_kyc_review(uuid, boolean, text) from public, anon;
