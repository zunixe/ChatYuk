-- ============================================
-- ChatYuk: DUMMY ACCOUNTS (alat uji admin)
-- Admin membuat akun dummy untuk pengujian chat:
--   - daftarkan akun (baru via signUp / akun yang sudah ada)
--   - set status online/idle/offline
--   - hapus akun + history chat
-- Semua akses admin-only (zunixe@gmail.com).
-- ============================================

-- ── 1. Tabel dummy_accounts ──
create table if not exists public.dummy_accounts (
  uid        uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  password   text not null,
  nickname   text not null,
  created_at timestamptz not null default now()
);

alter table public.dummy_accounts enable row level security;

drop policy if exists dummy_admin_all on public.dummy_accounts;
create policy dummy_admin_all on public.dummy_accounts
  for all using (coalesce(auth.email(), '') = 'zunixe@gmail.com');

revoke all on table public.dummy_accounts from anon;
revoke all on table public.dummy_accounts from authenticated;
grant select, insert, update, delete on table public.dummy_accounts to authenticated;

-- ── 2. Cari uid dari email (auth.users) ──
create or replace function public.admin_get_uid_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select id into v_uid from auth.users where email = p_email limit 1;
  return v_uid;
end;
$$;
revoke execute on function public.admin_get_uid_by_email(text) from public, anon;
grant execute on function public.admin_get_uid_by_email(text) to authenticated, service_role;

-- ── 3. Verifikasi password akun yang sudah ada (bcrypt compare) ──
create or replace function public.admin_verify_credentials(p_email text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select encrypted_password into v_hash from auth.users where email = p_email limit 1;
  if v_hash is null then
    return false;
  end if;
  return crypt(p_password, v_hash) = v_hash;
end;
$$;
revoke execute on function public.admin_verify_credentials(text, text) from public, anon;
grant execute on function public.admin_verify_credentials(text, text) to authenticated, service_role;

-- ── 4. Daftarkan akun sebagai dummy ──
-- Konfirmasi email, pastikan profil ada, simpan kredensial.
create or replace function public.admin_register_dummy(p_uid uuid, p_email text, p_password text, p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  -- Konfirmasi email (akun baru hasil signUp belum terkonfirmasi).
  update auth.users
     set email_confirmed_at = coalesce(email_confirmed_at, now())
   where id = p_uid;

  -- Pastikan profil ada (dummy bisa langsung diset status / dipakai chat).
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered)
  values (p_uid, p_nickname, 'male', 25, 'Indonesia', 'Jakarta', 'offline', true)
  on conflict (id) do update
    set nickname = excluded.nickname,
        is_registered = true;

  insert into public.dummy_accounts (uid, email, password, nickname)
  values (p_uid, p_email, p_password, p_nickname)
  on conflict (uid) do update
    set email = excluded.email,
        password = excluded.password,
        nickname = excluded.nickname;

  return jsonb_build_object('ok', true, 'uid', p_uid::text);
end;
$$;
revoke execute on function public.admin_register_dummy(uuid, text, text, text) from public, anon;
grant execute on function public.admin_register_dummy(uuid, text, text, text) to authenticated, service_role;

-- ── 5. List dummy + status profil ──
create or replace function public.admin_list_dummies()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'uid', d.uid::text,
      'email', d.email,
      'password', d.password,
      'nickname', coalesce(p.nickname, d.nickname),
      'status', coalesce(p.status, 'offline'),
      'last_seen', p.last_seen,
      'created_at', d.created_at
    ) order by d.created_at desc
  ), '[]'::jsonb) into result
  from public.dummy_accounts d
  left join public.profiles p on p.id = d.uid;
  return result;
end;
$$;
revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;

-- ── 6. Set status dummy (online / idle / offline) ──
create or replace function public.admin_set_dummy_status(p_uid uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_status not in ('online', 'idle', 'offline') then
    raise exception 'Status tidak valid';
  end if;
  update public.profiles
     set status = p_status, last_seen = now()
   where id = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.admin_set_dummy_status(uuid, text) from public, anon;
grant execute on function public.admin_set_dummy_status(uuid, text) to authenticated, service_role;

-- ── 7. Hapus dummy + history chat ──
-- private_chats dihapus → private_messages ikut cascade.
-- coin_ledger append-only: trigger di-disable sementara.
create or replace function public.admin_delete_dummy(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chats int;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  delete from public.private_chats where p_uid = any (participants);
  get diagnostics v_chats = row_count;

  delete from public.room_presence where user_id = p_uid;
  delete from public.user_photos where user_id = p_uid;

  -- Ledger append-only: nonaktifkan trigger delete untuk pembersihan dummy.
  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from public.dummy_accounts where uid = p_uid;
  delete from auth.users where id = p_uid; -- cascade ke profiles

  return jsonb_build_object('ok', true, 'chats_deleted', v_chats);
end;
$$;
revoke execute on function public.admin_delete_dummy(uuid) from public, anon;
grant execute on function public.admin_delete_dummy(uuid) to authenticated, service_role;
