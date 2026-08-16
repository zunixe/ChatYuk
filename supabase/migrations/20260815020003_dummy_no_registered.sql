-- ── 20003: Dummy tanpa centang verified + RPC is_dummy_account ──
-- 1. Dummy = is_registered false (seperti anonymous), + backfill profil lama.
update public.profiles set is_registered = false
where id in (select uid from public.dummy_accounts);

-- 2. Backfill participant_registered di private_chats yang melibatkan dummy.
update public.private_chats pc
set participant_registered = (
  select coalesce(jsonb_object_agg(p.id::text, p.is_registered), '{}'::jsonb)
  from public.profiles p where p.id = any(pc.participants)
)
where pc.participants && (select array_agg(uid) from public.dummy_accounts);

-- 3. Dummy baru dibuat dengan is_registered false.
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
  if p_age < 13 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered, last_seen)
  values (p_uid, p_nickname, p_gender, p_age, p_country, p_city, 'offline', false, now())
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
revoke execute on function public.admin_register_dummy(uuid, text, text, text, int, text, text) from public, anon;
grant execute on function public.admin_register_dummy(uuid, text, text, text, int, text, text) to authenticated, service_role;

-- 4. Cek apakah sebuah uid adalah dummy (untuk restore sesi di app).
create or replace function public.is_dummy_account(p_uid uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() <> p_uid and coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  return exists (select 1 from public.dummy_accounts where uid = p_uid);
end;
$$;
revoke execute on function public.is_dummy_account(uuid) from public, anon;
grant execute on function public.is_dummy_account(uuid) to authenticated, service_role;
