-- Daftar user terdaftar (email registrasi) untuk panel admin.
create or replace function public.admin_registrations_list(p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from profiles where is_registered = true),
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
     order by created_at desc
     limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) p;

  return result;
end;
$fn$;

revoke execute on function public.admin_registrations_list(integer,integer) from public, anon;
