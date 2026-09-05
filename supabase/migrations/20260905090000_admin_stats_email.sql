create or replace function public.admin_stats_detail()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  result jsonb;
  v_excl uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select array(select uid) into v_excl from public.admin_excluded_uids() ae;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'nickname', nickname, 'email', email,
        'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_excl))), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'nickname', nickname, 'email', email,
        'gender', gender, 'age', age,
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
        'id', id, 'nickname', nickname, 'email', email,
        'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles
      where is_registered = true and not (id = any(v_excl))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'nickname', nickname, 'email', email,
        'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by nickname)
      from profiles
      where is_registered = false
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
end; $$;
