-- Admin Ringkasan: UID manual blocklist (pelengkap exclude per-device).
--
-- Latar: exclude perangkat memetakan install_id -> user_id via user_devices.
-- Akun anon yang TIDAK punya baris user_devices (login anon tidak memanggil
-- syncToServer sebelum fix client, atau sync gagal diam-diam) lolos dari
-- filter dan tetap tampil di ringkasan (kasus: anon "jdjjds", "aqila").
-- Kolom app_settings.excluded_uids menampung daftar UID manual yang ikut
-- dibuang dari SEMUA metrik/list users via admin_excluded_uids().
--
-- Pola SETOF uuid: referensi WAJIB pakai alias ("from ... ae"),
-- JANGAN "select uid from admin_excluded_uids()" (42703).

alter table public.app_settings
  add column if not exists excluded_uids jsonb not null default '[]'::jsonb;

-- Helper: device-excluded + UID manual -> satu daftar uuid.
create or replace function public.admin_excluded_uids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $fn$
  select d.user_id
  from public.user_devices d
  where d.install_id in (
    select jsonb_array_elements_text(excluded_devices)
    from public.app_settings where id = 'global'
  )
  group by d.user_id
  union
  select value::uuid
  from public.app_settings,
       lateral jsonb_array_elements_text(
         case when jsonb_typeof(excluded_uids) = 'array'
              then excluded_uids else '[]'::jsonb end
       ) as value
  where id = 'global'
    and value ~* '^[0-9a-f-]{36}$';
$fn$;

-- Get / set daftar UID manual (guard admin, cache stats dihanguskan).
create or replace function public.admin_get_excluded_uids()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_list jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  select excluded_uids into v_list
    from public.app_settings where id = 'global';
  return coalesce(v_list, '[]'::jsonb);
end;
$fn$;

create or replace function public.admin_set_excluded_uids(p_list jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_clean jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_list is null or jsonb_typeof(p_list) <> 'array' then
    raise exception 'p_list must be a JSON array';
  end if;

  select coalesce(jsonb_agg(distinct t), '[]'::jsonb) into v_clean
    from jsonb_array_elements_text(p_list) as t
    where t ~* '^[0-9a-f-]{36}$';

  update public.app_settings
     set excluded_uids = coalesce(v_clean, '[]'::jsonb),
         updated_at = now()
   where id = 'global';

  delete from public.admin_stats_cache where id = 1;

  return coalesce(v_clean, '[]'::jsonb);
end;
$fn$;

revoke execute on function public.admin_get_excluded_uids() from public, anon;
revoke execute on function public.admin_set_excluded_uids(jsonb) from public, anon;
grant execute on function public.admin_get_excluded_uids() to authenticated, service_role;
grant execute on function public.admin_set_excluded_uids(jsonb) to authenticated, service_role;

-- Backfill: anon tanpa baris device yang dilapor (jdjjds + aqila).
update public.app_settings
   set excluded_uids = (
         select coalesce(jsonb_agg(distinct x order by x), '[]'::jsonb)
           from (
                  select jsonb_array_elements_text(excluded_uids) as x
                    from public.app_settings where id = 'global'
                   union
                  select '8184fa55-3956-48b2-8a02-195a1a7a6cc1'
                   union
                  select '9506be53-0270-412b-b392-b8672b14d683'
                ) t
          where x ~* '^[0-9a-f-]{36}$'
       ),
       updated_at = now()
 where id = 'global';

-- Ringkasan langsung segar.
delete from public.admin_stats_cache where id = 1;
