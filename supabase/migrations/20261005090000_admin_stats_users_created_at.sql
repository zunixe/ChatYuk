-- ============================================================
-- admin_stats_users_page: sertakan `created_at` (tanggal register akun).
--
-- LATAR: admin ingin melihat TANGGAL REGISTER tiap user di list Perangkat
--   (Per User). Sebelumnya item hanya memuat `last_seen` — tidak ada info
--   kapan akun dibuat.
--
-- PERUBAHAN: TAMBAH satu field 'created_at' pada jsonb item. Sisa fungsi
--   SALIN PERSIS dari versi live (header `-- menyentuh` tidak perlu:
--   admin_stats_users_page BUKAN FROZEN). Bukan ubah semantik filter.
--
-- CARA APPLY: Management API (1 statement create fn + revoke/grant).
-- ============================================================

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
as $function$
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
     where not (p.id = any(v_dummy))
       and not (p.id = any(v_excl))
       and not (coalesce(p.needs_onboarding, false) and not coalesce(p.is_registered, false))
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
     order by b.created_at desc nulls last, b.id
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
        'created_at', created_at,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last, id)
      from page
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

revoke execute on function public.admin_stats_users_page(text, integer, integer) from public, anon;
grant execute on function public.admin_stats_users_page(text, integer, integer) to authenticated, service_role;

-- Verifikasi setelah apply:
--   select public.admin_stats_users_page('all',1,0)->'items'->0->>'created_at';
