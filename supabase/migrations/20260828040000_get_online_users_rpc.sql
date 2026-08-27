-- RPC ringan untuk 1000 online: 1 RTT, server-side, tanpa IN (500 uuid)
create or replace function public.get_online_users(p_limit int default 100)
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'nickname', nickname, 'gender', gender, 'age', age,
    'country', country, 'city', city, 'status', status, 'avatar', avatar,
    'is_registered', is_registered, 'last_seen', last_seen
  ) order by last_seen desc), '[]'::jsonb)
  from (
    select id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen
    from public.profiles
    where status not in ('offline','invisible')
      and last_seen >= now() - interval '30 minutes'
    order by last_seen desc
    limit greatest(p_limit, 1)
  ) s;
$$;

grant execute on function public.get_online_users(int) to authenticated, anon;
