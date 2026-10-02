-- ============================================================
-- admin_stats_users_page: urutkan berdasar AKUN TERBARU (created_at desc).
--
-- LATAR (2026-10-01): admin Overview ingin sheet "User Reg/Anon" menampilkan
--   user yang BARU DIBUAT AKUNNYA paling atas (created_at desc) — bukan
--   yang paling baru online (last_seen). (Perubahan sebelumnya sempat
--   mengubah urutan ke last_seen; dikembalikan ke created_at sesuai maksud
--   admin.)
--
--   Filter "user dengan device ter-exclude disembunyikan total" TETAP
--   dipertahankan (and not (p.id = any(v_excl))).
--
-- PERUBAHAN dari versi sebelumnya:
--   - ordering: `created_at desc nulls last, id` untuk SEMUA kind.
--   - filter excluded tetap.
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.admin_stats_users_page(p_kind text default 'all'::text, p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
stable security definer
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
       -- User dengan device ter-exclude disembunyikan total (bukan sekedar
       -- diberi badge).
       and not (p.id = any(v_excl))
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
     -- AKUN TERBARU di atas (created_at desc). Tie-break id agar paginasi stabil.
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
--   select pg_get_functiondef('public.admin_stats_users_page(text,integer,integer)'::regprocedure)
--     like '%order by b.created_at desc%';                       -- true
--   select pg_get_functiondef('public.admin_stats_users_page(text,integer,integer)'::regprocedure)
--     like '%not (p.id = any(v_excl))%';                          -- true
