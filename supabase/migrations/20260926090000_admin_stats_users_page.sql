-- admin_stats_users_page: daftar user statistik ber-paginasi.
--
-- LATAR: admin_stats_detail (FROZEN — JANGAN disentuh) mengembalikan 4×
-- FULL list profiles (users_all/active/registered/anonymous) dalam 1
-- panggilan. Di skala 100× (16k user) itu puluhan ribu objek JSON per buka
-- sheet. Fungsi ini FUNGSI BARU (bukan replace) dengan filter + bentuk baris
-- + urutan yang SAMA persis, ditambah paginasi limit/offset.
-- Dipakai stat_detail_sheet untuk 4 kunci user; rooms_active/messages_today
-- tetap dari detail (kecil & teragregasi).
create or replace function public.admin_stats_users_page(
  p_kind text default 'all',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_kind not in ('all','active','registered','anonymous') then
    p_kind := 'all';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  with base as (
    select p.*
      from public.profiles p
     where not (p.id = any(v_excl))
       and not (p.id = any(v_dummy))
       and case p_kind
             when 'active' then
               p.last_seen >= current_date at time zone 'Asia/Jakarta'
             when 'registered' then p.is_registered = true
             when 'anonymous' then coalesce(p.is_registered, false) = false
             else true
           end
  ),
  counted as (select count(*) as total from base),
  page as (
    select b.*
      from base b
     order by case when p_kind = 'registered'
                   then b.created_at end desc nulls last,
              case when p_kind <> 'registered'
                   then b.last_seen end desc nulls last,
              b.id
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select total from counted),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by case when p_kind = 'registered'
                      then created_at end desc nulls last,
                 case when p_kind <> 'registered'
                      then last_seen end desc nulls last,
                 id)
      from page
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$fn$;

revoke execute on function public.admin_stats_users_page(text, integer, integer)
  from public, anon;
grant execute on function public.admin_stats_users_page(text, integer, integer)
  to authenticated, service_role;
