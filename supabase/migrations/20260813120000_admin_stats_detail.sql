-- ============================================================
-- ChatYuk: Detail data untuk card statistik Overview
-- Card di Overview bisa diklik → lihat siapa saja user-nya.
-- RPC ini mengembalikan list detail untuk setiap statistik.
-- ============================================================

create or replace function public.admin_stats_detail()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
        'country', country, 'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by last_seen desc nulls last)
      from profiles), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by nickname)
      from profiles where is_registered = true), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'status', status,
        'is_registered', is_registered, 'last_seen', last_seen
      ) order by nickname)
      from profiles where is_registered = false), '[]'::jsonb),
    'rooms_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'room_id', room_id, 'user_count', c
      ) order by c desc)
      from (select room_id, count(*) as c from room_presence group by room_id) t), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;
revoke execute on function public.admin_stats_detail() from public, anon;
grant execute on function public.admin_stats_detail() to authenticated, service_role;
