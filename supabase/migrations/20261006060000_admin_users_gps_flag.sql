-- ============================================================
-- Admin "Per User": kirim status LOKASI (Fake GPS vs GPS asli).
--
-- Permintaan user: di daftar user admin, admin ingin tahu MANA yang pakai
-- Fake GPS dan mana GPS asli.
--
-- `admin_stats_users_page` sudah mengirim lat/lon/loc_source; tambah:
--   - lat_gps, lon_gps, gps_updated_at : koordinat GPS terakhir (null = tak
--     pernah kirim GPS → sumbernya IP).
--   - location_mocked + location_mock_reason : hasil deteksi server
--     (is_mocked/accuracy_zero/impossible_speed/spoof_delta/known_emulator/
--     static_coord/shared_coord) — dipakai UI menampilkan badge "Fake GPS".
--
-- Body lain IDENTIK. Idempotent (create or replace). TIDAK FROZEN.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_stats_users_page(p_kind text DEFAULT 'all'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        'lat_gps', lat_gps, 'lon_gps', lon_gps, 'gps_updated_at', gps_updated_at,
        'location_mocked', coalesce(location_mocked, false),
        'location_mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last, id)
      from page
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$
