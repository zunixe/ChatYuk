-- Ringkasan admin: bar chart registrasi email + peta user buang dummy/excluded.
--
-- Latar:
-- 1) admin_registrations_daily (bar chart Ringkasan) & admin_registrations_list
--    (bottom sheet) belum memfilter akun dummy + user device-ter-exclude,
--    padahal card Registered Users (admin_stats_compute) sudah.
-- 2) Peta user (_UserMapCard) load dari users_all (sudah bersih) TAPI
--    realtime INSERT/UPDATE profiles langsung masuk ke _users tanpa filter —
--    dummy & user ter-exclude bisa muncul sebagai pin via jalur realtime.
--    users_all belum membawa 'id' sehingga pencocokan realtime pun goyah.
--
-- Isi: samakan filter v_excl/v_dummy ke kedua RPC registrasi, tambahkan 'id'
-- ke users_all, RPC admin_hidden_uids() untuk filter client-side.

-- 1) Bar chart: exclude dummy + device-ter-exclude (pola admin_stats_compute).
create or replace function public.admin_registrations_daily(p_year int, p_month int)
returns table (day int, count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'forbidden';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;
  return query
    select extract(day from p.created_at)::int as d,
           count(*)::bigint as c
      from profiles p
     where p.is_registered = true
       and not (p.id = any(v_excl))
       and not (p.id = any(v_dummy))
       and extract(year from p.created_at) = p_year
       and extract(month from p.created_at) = p_month
     group by 1
     order by 1;
end;
$$;

-- 2) Bottom sheet list registrasi: filter yang sama (total + items).
create or replace function public.admin_registrations_list(p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'total', (select count(*) from profiles
      where is_registered = true
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'user_id',     p.id,
        'nickname',    p.nickname,
        'email',       p.email,
        'gender',      p.gender,
        'age',         p.age,
        'country',     p.country,
        'city',        p.city,
        'ip_address',  p.ip_address,
        'created_at',  p.created_at,
        'last_seen_at', p.last_seen
      ) order by p.created_at desc
    ), '[]'::jsonb)
  ) into result
  from (
    select *
      from profiles
     where is_registered = true
       and not (id = any(v_excl))
       and not (id = any(v_dummy))
     order by created_at desc
     limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) p;

  return result;
end;
$fn$;

-- 3) users_all: bawa 'id' supaya filter realtime client bisa mencocokkan
--    (sebelumnya tanpa id → fallback nickname+ip, entry baru lolos filter).
--    Filter server tetap: buang dummy + device-ter-exclude.
create or replace function public.admin_stats_detail()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by nickname)
      from profiles where is_registered = true
        and not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by nickname)
      from profiles where is_registered = false
        and not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'rooms_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'room_id', t.room_id,
        'room_name', coalesce(r.name, t.room_id),
        'is_private', coalesce(r.is_private, false),
        'user_count', t.c
      ) order by t.c desc)
      from (select room_id, count(*) as c from room_presence group by room_id) t
      left join rooms r on r.id = t.room_id), '[]'::jsonb),
    'messages_today', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'sender_name', sender_name,
          'text', case when type = 'image' then '[foto]' else text end,
          'type', type,
          'created_at', created_at
        ) as x
        from private_messages
        where created_at >= current_date at time zone 'Asia/Jakarta'
        order by created_at desc
        limit 200
      ) sub), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

-- 4) Daftar UID tersembunyi untuk filter client-side (peta realtime).
create or replace function public.admin_hidden_uids()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'dummy', coalesce((
      select jsonb_agg(du) from public.admin_dummy_uids() du), '[]'::jsonb),
    'excluded', coalesce((
      select jsonb_agg(ae) from public.admin_excluded_uids() ae), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_hidden_uids() from public, anon;
grant execute on function public.admin_hidden_uids() to authenticated, service_role;

-- 5) Ringkasan langsung segar.
delete from public.admin_stats_cache where id = 1;
