-- Dummy = akun anonymous (tanpa email/password).
-- Swap sesi via refresh_token (GoTrue memutar token tiap setSession,
-- jadi token di DB selalu di-update setelah setiap swap).

-- 1. Ubah tabel: buang email/password, simpan refresh_token
alter table public.dummy_accounts
  drop column if exists email,
  drop column if exists password,
  add column if not exists refresh_token text;

-- 2. Daftarkan dummy (akun anonymous sudah dibuat oleh edge function)
drop function if exists public.admin_register_dummy(uuid, text, text, text);
create or replace function public.admin_register_dummy(p_uid uuid, p_nickname text, p_refresh_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered, last_seen)
  values (p_uid, p_nickname, 'male', 25, 'Indonesia', 'Jakarta', 'offline', true, now())
  on conflict (id) do update set
    nickname = excluded.nickname,
    last_seen = now();
  insert into public.dummy_accounts (uid, nickname, refresh_token)
  values (p_uid, p_nickname, p_refresh_token)
  on conflict (uid) do update set
    nickname = excluded.nickname,
    refresh_token = excluded.refresh_token;
  return jsonb_build_object('ok', true, 'uid', p_uid);
end;
$$;
revoke execute on function public.admin_register_dummy(uuid, text, text) from public, anon;
grant execute on function public.admin_register_dummy(uuid, text, text) to authenticated, service_role;

-- 3. List dummy (tanpa kredensial)
drop function if exists public.admin_list_dummies();
create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows jsonb[];
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;
revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;

-- 4. Ambil refresh_token dummy (untuk swap sesi dari app)
create or replace function public.admin_get_dummy_token(p_uid uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select refresh_token into v_token from public.dummy_accounts where uid = p_uid;
  return v_token;
end;
$$;
revoke execute on function public.admin_get_dummy_token(uuid) from public, anon;
grant execute on function public.admin_get_dummy_token(uuid) to authenticated, service_role;

-- 5. Update refresh_token setelah rotasi GoTrue
create or replace function public.admin_update_dummy_token(p_uid uuid, p_refresh_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  update public.dummy_accounts set refresh_token = p_refresh_token where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.admin_update_dummy_token(uuid, text) from public, anon;
grant execute on function public.admin_update_dummy_token(uuid, text) to authenticated, service_role;

-- 6. Buang fungsi lama berbasis email (tidak dipakai lagi)
drop function if exists public.admin_verify_credentials(text, text);
drop function if exists public.admin_get_uid_by_email(text);

-- 7. cleanup_stale_anonymous: jangan pernah hapus akun dummy
create or replace function public.cleanup_stale_anonymous(min_age_days int default 7)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted int := 0;
  r record;
begin
  for r in
    select u.id
    from auth.users u
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.dummy_accounts d where d.uid = u.id
      )
      and not exists (
        select 1 from public.profiles p
        where p.id = u.id
          and p.last_seen > now() - make_interval(days => min_age_days)
      )
  loop
    delete from public.room_presence where user_id = r.id;
    delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
    delete from public.reports where reporter_id = r.id or reported_id = r.id;
    delete from public.user_photos where user_id = r.id;

    delete from public.private_messages pm
    using public.private_chats pc
    where pm.chat_id = pc.chat_id
      and pc.participants @> array[r.id]::uuid[];

    delete from public.private_chats pc
    where pc.participants @> array[r.id]::uuid[];

    delete from public.private_messages where sender_id = r.id;

    delete from public.profiles where id = r.id;
    delete from auth.users where id = r.id;
    deleted := deleted + 1;
  end loop;
  return deleted;
end;
$$;

revoke execute on function public.cleanup_stale_anonymous(int) from public, anon;
grant execute on function public.cleanup_stale_anonymous(int) to authenticated, service_role;
