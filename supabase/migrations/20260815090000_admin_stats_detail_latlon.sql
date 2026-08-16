-- ============================================================
-- ChatYuk: admin_stats_detail — sertakan lat/lon & loc_source
-- untuk link Google Maps yang akurat (pin koordinat, bukan search kota).
-- ============================================================

create or replace function public.admin_stats_detail()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by last_seen desc nulls last)
      from profiles), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by nickname)
      from profiles where is_registered = true), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by nickname)
      from profiles where is_registered = false), '[]'::jsonb),
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

revoke execute on function public.admin_stats_detail() from public, anon;
grant execute on function public.admin_stats_detail() to authenticated, service_role;
