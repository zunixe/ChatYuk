-- Dummy profile: gender, umur, negara, kota bisa di-set dari admin panel.

-- 1. Register dummy dengan profil lengkap
drop function if exists public.admin_register_dummy(uuid, text, text);
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
revoke execute on function public.admin_register_dummy(uuid, text, text, text, int, text, text) from public, anon;
grant execute on function public.admin_register_dummy(uuid, text, text, text, int, text, text) to authenticated, service_role;

-- 2. Update profil dummy (tanpa menyentuh status/refresh_token)
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
  if p_age < 13 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  update public.profiles
  set nickname = p_nickname, gender = p_gender, age = p_age,
      country = p_country, city = p_city, last_seen = now()
  where id = p_uid;
  update public.dummy_accounts set nickname = p_nickname where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.admin_update_dummy_profile(uuid, text, text, int, text, text) from public, anon;
grant execute on function public.admin_update_dummy_profile(uuid, text, text, int, text, text) to authenticated, service_role;

-- 3. List dummy sertakan gender/umur/negara/kota
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
    'gender', p.gender,
    'age', p.age,
    'country', p.country,
    'city', p.city,
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
