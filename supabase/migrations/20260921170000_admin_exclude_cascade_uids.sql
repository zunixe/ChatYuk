-- Exclude per-device RAPUH: install_id (ANDROID_ID) bisa BERUBAH untuk HP
-- yang sama — Android 8+ meng-scope ANDROID_ID ke (device + user profile +
-- app signing key). Akibatnya satu HP bisa punya >1 install_id (terbukti:
-- 24129PN74G punya android-2f218335e9fd56d5 DAN android-e29a2f7c3e9624c6),
-- sehingga device yang sudah di-exclude "muncul lagi" sebagai device baru.
--
-- Perbaikan dua lapis:
--   1) `admin_list_devices` kini memakai `admin_excluded_uids()` (device +
--      uid manual) supaya UID yang di-exclude konsisten disembunyikan ——
--      sebelumnya fungsi ini HANYA melihat `excluded_devices`.
--   2) `admin_exclude_device_cascade(p_install_id)`: exclude 1 device SEKALIGUS
--      menambahkan semua uid yang pernah login di device itu ke `excluded_uids`
--      → walau install_id berubah (Second Space/Dual Apps/keystore beda),
--      user tetap ter-exclude (filter berbasis uid, bukan device).
--
-- Catatan: `admin_stats_detail` FROZEN — TIDAK disentuh di sini.
-- `admin_list_devices` tidak frozen; snapshot `functions.sql` tidak memuatnya
-- (hanya fungsi yang di-snapshot), jadi tidak perlu update snapshot.

-- ── 1) admin_list_devices: gunakan gabungan admin_excluded_uids() ──
create or replace function public.admin_list_devices(
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_total bigint;
  v_excl uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  select greatest(count(*), 0)::bigint into v_total
    from public.user_devices d
    where d.install_id not in (
      select jsonb_array_elements_text(excluded_devices)
      from public.app_settings where id = 'global'
    )
      and (d.user_id is null or not (d.user_id = any(v_excl)));

  select jsonb_build_object(
    'total', coalesce(v_total, 0),
    'items', coalesce((
      select jsonb_agg(sub.obj order by sub.last_seen_at desc nulls last)
      from (
        select
          jsonb_build_object(
            'user_id',      p.id,
            'nickname',     p.nickname,
            'email',        p.email,
            'is_registered', p.is_registered,
            'profile_status', p.status,
            'install_id',   d.install_id,
            'brand',        d.brand,
            'model',        d.model,
            'os_name',      d.os_name,
            'os_version',   d.os_version,
            'app_version',  d.app_version,
            'ip_address',   d.ip_address,
            'last_seen_at', d.last_seen_at,
            'is_active',    d.is_active,
            'created_at',   d.created_at
          ) as obj,
          d.last_seen_at
        from public.user_devices d
        left join public.profiles p on p.id = d.user_id
        where d.install_id not in (
          select jsonb_array_elements_text(excluded_devices)
          from public.app_settings where id = 'global'
        )
          and (d.user_id is null or not (d.user_id = any(v_excl)))
        order by d.last_seen_at desc nulls last
        limit greatest(p_limit, 1) offset greatest(p_offset, 0)
      ) sub
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_list_devices(integer,integer)
  from public, anon;
grant execute on function public.admin_list_devices(integer,integer)
  to authenticated, service_role;

-- ── 2) Cascade exclude: device → semua uid-nya ikut excluded_uids ──
create or replace function public.admin_exclude_device_cascade(p_install_id text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare
  v_install text := nullif(trim(coalesce(p_install_id, '')), '');
  v_devices jsonb;
  v_uids jsonb;
  v_added jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if v_install is null then
    raise exception 'p_install_id kosong';
  end if;

  -- Tambah install_id ke excluded_devices (unik).
  select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into v_devices
    from (
      select jsonb_array_elements_text(
               case when jsonb_typeof(excluded_devices) = 'array'
                    then excluded_devices else '[]'::jsonb end) as x
        from public.app_settings where id = 'global'
      union
      select v_install
    ) t;

  -- Kumpulkan SEMUA uid yang pernah login di device ini → tambah ke
  -- excluded_uids supaya exclude tahan walau install_id berubah.
  select coalesce(jsonb_agg(distinct u::text), '[]'::jsonb) into v_uids
    from (
      select jsonb_array_elements_text(
               case when jsonb_typeof(excluded_uids) = 'array'
                    then excluded_uids else '[]'::jsonb end) as u
        from public.app_settings where id = 'global'
      union
      select d.user_id::text
        from public.user_devices d
       where d.install_id = v_install
         and d.user_id is not null
    ) s
   where u ~* '^[0-9a-f-]{36}$';

  update public.app_settings
     set excluded_devices = coalesce(v_devices, '[]'::jsonb),
         excluded_uids    = coalesce(v_uids, '[]'::jsonb),
         updated_at       = now()
   where id = 'global';

  -- Ringkasan langsung segar.
  delete from public.admin_stats_cache where id = 1;

  v_added := coalesce(v_uids, '[]'::jsonb);
  return jsonb_build_object('devices', v_devices, 'uids', v_added);
end;
$fn$;

revoke execute on function public.admin_exclude_device_cascade(text)
  from public, anon;
grant execute on function public.admin_exclude_device_cascade(text)
  to authenticated, service_role;

-- ── 3) Backfill sekali: uid dari device yang SUDAH ter-exclude ──
-- Supaya exclude lama (sebelum cascade ada) juga tahan install_id berubah.
with cur as (
  select
    case when jsonb_typeof(excluded_devices) = 'array'
         then excluded_devices else '[]'::jsonb end as devs,
    case when jsonb_typeof(excluded_uids) = 'array'
         then excluded_uids else '[]'::jsonb end as uids
  from public.app_settings where id = 'global'
),
merged as (
  select coalesce(jsonb_agg(distinct u::text), '[]'::jsonb) as uids
  from (
    select jsonb_array_elements_text((select uids from cur)) as u
    union
    select d.user_id::text
      from public.user_devices d
     where d.install_id in (select jsonb_array_elements_text((select devs from cur)))
       and d.user_id is not null
  ) s
  where u ~* '^[0-9a-f-]{36}$'
)
update public.app_settings
   set excluded_uids = (select uids from merged),
       updated_at = now()
 where id = 'global';

delete from public.admin_stats_cache where id = 1;
