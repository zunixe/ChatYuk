-- ============================================================
-- ChatYuk — Admin: sebaran GEOGRAFIS user (negara → kota).
--
-- Permintaan user: di admin "Ringkasan" tampilkan CHART negara mana yang
-- paling banyak usernya; klik negara → daftar kota + jumlahnya.
--
-- Dua RPC (baca agregat, admin-only):
--   admin_country_stats()          → [{country, count, registered}] desc by count
--   admin_city_stats(p_country)    → [{city, count, registered}]    desc by count
--
-- Aturan hitung = SAMA dgn admin_stats_compute (exclude excluded-uids &
-- dummy; anon placeholder onboarding dikecualikan untuk konsistensi angka).
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_country_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  res jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select coalesce(jsonb_agg(t order by t.count desc, t.country), '[]'::jsonb)
    into res
  from (
    select
      coalesce(nullif(btrim(country), ''), 'Tidak diketahui') as country,
      count(*) as count,
      count(*) filter (where is_registered) as registered
    from public.profiles
    where not (id = any(v_excl))
      and not (id = any(v_dummy))
      and coalesce(needs_onboarding, false) = false
    group by 1
  ) t;

  return coalesce(res, '[]'::jsonb);
end;
$function$;

revoke execute on function public.admin_country_stats() from public, anon; -- SAFE: agregat admin-only
grant execute on function public.admin_country_stats() to authenticated; -- SAFE: dipakai panel admin (guard email di body)

CREATE OR REPLACE FUNCTION public.admin_city_stats(p_country text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  v_country text := coalesce(nullif(btrim(coalesce(p_country, '')), ''), 'Tidak diketahui');
  res jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select coalesce(jsonb_agg(t order by t.count desc, t.city), '[]'::jsonb)
    into res
  from (
    select
      coalesce(nullif(btrim(city), ''), 'Tidak diketahui') as city,
      count(*) as count,
      count(*) filter (where is_registered) as registered
    from public.profiles
    where coalesce(nullif(btrim(country), ''), 'Tidak diketahui') = v_country
      and not (id = any(v_excl))
      and not (id = any(v_dummy))
      and coalesce(needs_onboarding, false) = false
    group by 1
  ) t;

  return coalesce(res, '[]'::jsonb);
end;
$function$;

revoke execute on function public.admin_city_stats(text) from public, anon; -- SAFE: agregat admin-only
grant execute on function public.admin_city_stats(text) to authenticated; -- SAFE: dipakai panel admin (guard email di body)
