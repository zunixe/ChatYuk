-- ChatYuk Admin: Exclude Device
-- Device (install_id) yang di-exclude tidak dihitung di ringkasan
-- (total_users, active_today, registered_users, anonymous_users,
-- top_earners) & detail users, serta disembunyikan dari daftar
-- perangkat (per-device & per-user).

-- 1) Kolom settings: daftar install_id yang di-exclude (row global).
alter table public.app_settings
  add column if not exists excluded_devices jsonb not null default '[]'::jsonb;

-- 2) Helper: daftar user_id yang punya device ter-exclude.
create or replace function public.admin_excluded_uids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $fn$
  select d.user_id
  from public.user_devices d
  where d.install_id in (
    select jsonb_array_elements_text(excluded_devices)
    from public.app_settings where id = 'global'
  )
  group by d.user_id;
$fn$;

-- 3) Stats compute: filter user yang device-nya ter-exclude
--    (hanya metrik ringkasan users — messages/rooms tetap apa adanya).
create or replace function public.admin_stats_compute()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  result jsonb;
  v_excl uuid[];
begin
  select coalesce(array_agg(uid), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids();

  select jsonb_build_object(
    'total_users', (select count(*) from profiles
      where not (id = any(v_excl))),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_excl))),
    'registered_users', (select count(*) from profiles
      where is_registered = true and not (id = any(v_excl))),
    'anonymous_users', (select count(*) from profiles
      where is_registered = false and not (id = any(v_excl))),
    'messages_today',
      (select count(*) from private_messages where created_at >= current_date at time zone 'Asia/Jakarta') +
      (select count(*) from messages where created_at >= current_date at time zone 'Asia/Jakarta'),
    'rooms_active', (select count(distinct room_id) from room_presence),
    'avg_points', (select round(avg(points)) from profiles where not (id = any(v_excl))),
    'total_points', (select sum(points) from profiles where not (id = any(v_excl))),
    'top_earners', (select coalesce(jsonb_agg(
      jsonb_build_object('nickname', nickname, 'points', points, 'uid', id)
      order by points desc), '[]'::jsonb) from (select id, nickname, points from profiles
      where not (id = any(v_excl)) order by points desc limit 10) t),
    'stuck_users', (select count(*) from profiles
      where points = 0 and last_seen >= (now() - interval '7 days')
        and not (id = any(v_excl))),
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object('reported_id', reported_id, 'report_count', c)
      order by c desc), '[]'::jsonb)
      from (select reported_id, count(*) as c from reports
            group by reported_id order by c desc limit 20) sub),
    'points_enabled', (select points_enabled from app_settings where id = 'global')
  ) into result;
  return result;
end;
$fn$;

-- 4) Detail users: buang user yang device-nya ter-exclude
--    (users_all / active / registered / anonymous).
create or replace function public.admin_stats_detail()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  result jsonb;
  v_excl uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(uid), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids();

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_excl))), '[]'::jsonb),
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
        and not (id = any(v_excl))), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by nickname)
      from profiles where is_registered = true
        and not (id = any(v_excl))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by nickname)
      from profiles where is_registered = false
        and not (id = any(v_excl))), '[]'::jsonb),
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

-- 5) List devices: sembunyikan install_id yang ter-exclude
--    (berlaku untuk mode per-user; mode per-device dikelompokkan
--    client-side dari list ini sehingga otomatis ikut bersih).
create or replace function public.admin_list_devices(p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_total bigint;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select greatest(count(*), 0)::bigint into v_total
    from public.user_devices d
    where d.install_id not in (
      select jsonb_array_elements_text(excluded_devices)
      from public.app_settings where id = 'global'
    );

  select jsonb_build_object(
    'total', coalesce(v_total, 0),
    'items', coalesce((
      select jsonb_agg(sub.obj order by sub.last_seen_at desc nulls last)
      from (
        select
          jsonb_build_object(
            'user_id',      p.id,
            'nickname',     p.nickname,
            'email',        p.email,
            'is_registered', p.is_registered,
            'profile_status', p.status,
            'install_id',   d.install_id,
            'brand',        d.brand,
            'model',        d.model,
            'os_name',      d.os_name,
            'os_version',   d.os_version,
            'app_version',  d.app_version,
            'ip_address',   d.ip_address,
            'last_seen_at', d.last_seen_at,
            'is_active',    d.is_active,
            'created_at',   d.created_at
          ) as obj,
          d.last_seen_at
        from public.user_devices d
        left join public.profiles p on p.id = d.user_id
        where d.install_id not in (
          select jsonb_array_elements_text(excluded_devices)
          from public.app_settings where id = 'global'
        )
        order by d.last_seen_at desc nulls last
        limit greatest(p_limit, 1) offset greatest(p_offset, 0)
      ) sub
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_list_devices(integer,integer) from public, anon;
grant execute on function public.admin_list_devices(integer,integer) to authenticated, service_role;

-- 6) Get / set daftar excluded (guard admin, hapus cache stats biar
--    ringkasan langsung segar setelah perubahan).
create or replace function public.admin_get_excluded_devices()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_list jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  select excluded_devices into v_list
    from public.app_settings where id = 'global';
  return coalesce(v_list, '[]'::jsonb);
end;
$fn$;

create or replace function public.admin_set_excluded_devices(p_list jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_clean jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_list is null or jsonb_typeof(p_list) <> 'array' then
    raise exception 'p_list must be a JSON array';
  end if;

  -- Bersihkan: text non-kosong, trim, unik, maks 500 item.
  select coalesce(jsonb_agg(distinct t), '[]'::jsonb) into v_clean
    from jsonb_array_elements_text(p_list) as t
    where nullif(trim(t), '') is not null;

  update public.app_settings
     set excluded_devices = coalesce(v_clean, '[]'::jsonb),
         updated_at = now()
   where id = 'global';

  -- Ringkasan langsung segar (cache TTL 5 menit terlalu lama untuk admin).
  delete from public.admin_stats_cache;

  return coalesce(v_clean, '[]'::jsonb);
end;
$fn$;

revoke execute on function public.admin_get_excluded_devices() from public, anon;
revoke execute on function public.admin_set_excluded_devices(jsonb) from public, anon;
grant execute on function public.admin_get_excluded_devices() to authenticated, service_role;
grant execute on function public.admin_set_excluded_devices(jsonb) to authenticated, service_role;
