-- ============================================================
-- ChatYuk Wallet FASE 4 — KYC (Know Your Customer)
--
-- Gate sebelum pencairan (Fase 5): creator harus verifikasi identitas.
-- Data KYC disimpan di tabel terpisah (bukan profiles) — satu sumber
-- kebenaran; status dibaca via RPC get_my_kyc(). RLS mengunci: user
-- hanya bisa baca milik sendiri; tulis hanya via RPC security definer.
-- Foto disimpan sebagai base64 (konsisten pola view_once/chat).
-- ============================================================

create table if not exists public.kyc_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected')),
  full_name     text not null,
  id_type       text not null default 'ktp'
                check (id_type in ('ktp', 'passport')),
  id_number     text not null,
  id_photo      text not null,   -- base64 foto kartu identitas
  selfie_photo  text not null,   -- base64 foto selfie (satu frame dengan KTP)
  birth_date    date,
  reject_reason text,
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_kyc_requests_user  on public.kyc_requests(user_id, created_at desc);
create index if not exists idx_kyc_requests_status on public.kyc_requests(status, created_at desc);

alter table public.kyc_requests enable row level security;

-- User hanya bisa baca permohonan milik sendiri; admin bisa lihat semua.
drop policy if exists kyc_requests_select_own on public.kyc_requests;
create policy kyc_requests_select_own on public.kyc_requests
  for select using (
    user_id = auth.uid()
    or coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
  );

-- Tidak ada write dari client langsung (insert/update/delete via RPC definer).
revoke insert, update, delete on public.kyc_requests from anon, authenticated;
grant select on public.kyc_requests to anon, authenticated;

-- ============================================================
-- RPC: submit_kyc(...)
--   - hanya bila belum ada pending/approved aktif
--   - update_at otomatis
-- ============================================================
create or replace function public.submit_kyc(
  p_full_name text, p_id_type text, p_id_number text,
  p_id_photo text, p_selfie_photo text, p_birth_date date default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if length(trim(p_full_name)) < 3 then raise exception 'Invalid name'; end if;
  if length(trim(p_id_number)) < 8 then raise exception 'Invalid ID number'; end if;
  if length(p_id_photo) < 100 or length(p_selfie_photo) < 100 then
    raise exception 'Photos required'; end if;

  if exists (select 1 from kyc_requests
             where user_id = uid and status in ('pending', 'approved')) then
    raise exception 'KYC already submitted';
  end if;

  insert into kyc_requests (user_id, status, full_name, id_type, id_number,
                            id_photo, selfie_photo, birth_date)
  values (uid, 'pending', p_full_name, coalesce(p_id_type, 'ktp'), p_id_number,
          p_id_photo, p_selfie_photo, p_birth_date);

  return jsonb_build_object('ok', true, 'status', 'pending');
end; $$;
revoke execute on function public.submit_kyc(text, text, text, text, text, date) from public, anon;
grant execute on function public.submit_kyc(text, text, text, text, text, date) to authenticated;

-- ============================================================
-- RPC: get_my_kyc() — status KYC terbaru user sendiri
-- ============================================================
create or replace function public.get_my_kyc()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select to_jsonb(x) into res from (
    select id, status, full_name, id_type, id_number,
           birth_date, reject_reason, reviewed_at, created_at
    from kyc_requests where user_id = auth.uid()
    order by created_at desc limit 1
  ) x;
  if res is null then return jsonb_build_object('status', 'none'); end if;
  return res;
end; $$;
revoke execute on function public.get_my_kyc() from public, anon;
grant execute on function public.get_my_kyc() to authenticated;

-- ============================================================
-- RPC: admin_kyc_list(status) — review KYC (admin only)
--   - include foto (base64) untuk direview admin.
-- ============================================================
create or replace function public.admin_kyc_list(p_status text default 'pending')
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select k.id, k.user_id, k.status, k.full_name, k.id_type, k.id_number,
           k.id_photo, k.selfie_photo, k.birth_date, k.reject_reason, k.created_at,
           p.nickname, p.email
    from kyc_requests k
    join profiles p on p.id = k.user_id
    where (p_status = 'all' or k.status = p_status)
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.admin_kyc_list(text) from public, anon;
grant execute on function public.admin_kyc_list(text) to authenticated, service_role;

-- ============================================================
-- RPC: admin_kyc_review(request_id, approve, reason)
--   - approve → status 'approved'
--   - reject  → status 'rejected' + reject_reason
-- ============================================================
create or replace function public.admin_kyc_review(
  p_request_id uuid, p_approve boolean, p_reason text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;

  update kyc_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    reject_reason = case when p_approve then null else p_reason end,
    reviewed_by = uid,
    reviewed_at = now(),
    updated_at = now()
  where id = p_request_id;

  if not found then raise exception 'Request not found'; end if;
  return jsonb_build_object('ok', true, 'approved', p_approve);
end; $$;
revoke execute on function public.admin_kyc_review(uuid, boolean, text) from public, anon;
grant execute on function public.admin_kyc_review(uuid, boolean, text) to authenticated, service_role;
