-- Arsip riwayat device + GPS ke deleted_users agar tab Terhapus admin tetap
-- menampilkan info perangkat & lokasi walau baris live sudah dibersihkan.
--
-- MASALAH (laporan user: "info perangkatnya jangan dihapus di admin sama gpsnya"):
--   `delete_my_account` (20260923130000) & `admin_delete_anon_user` (20260921230000)
--   menghapus eksplisit `user_devices` + `user_location_history` SEBELUM
--   `delete from profiles` (wajib, kalau tidak 23502 NOT NULL).
--   Efek samping: `admin_deleted_device_history(nickname)` yang membaca
--   `user_devices.nickname_snapshot` selalu kosong untuk user yang baru dihapus,
--   dan riwayat GPS tidak ada RPC-nya sama sekali di tab Terhapus.
--
-- SOLUSI (arsip, bukan preserve live):
--   Live tables tetap dibersihkan (deletion tetap sukses + privasi + tidak ada
--   orphan "(profil terhapus)" di tab Perangkat). History disalin ke
--   `deleted_users.devices/locations` (jsonb) di `fn_archive_deleted_user`
--   SEBELUM baris live dihapus. Pembaca admin mengutamakan snapshot arsip,
--   fallback ke live untuk arsip lama.
--   Bukan fungsi FROZEN. Grant rutin (revoke execute) dikecualikan guard.

-- -- 1. Kolom arsip di deleted_users --
alter table public.deleted_users
  add column if not exists devices jsonb not null default '[]'::jsonb;
alter table public.deleted_users
  add column if not exists locations jsonb not null default '[]'::jsonb;

-- -- 2. fn_archive_deleted_user: snapshot devices + locations (dasar = live def) --
create or replace function public.fn_archive_deleted_user(
  p_uid uuid,
  p_reason text,
  p_claimed_by uuid default null,
  p_claimed_nick text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_nick text; v_email text; v_reg boolean; v_ip text;
  v_brand text; v_model text; v_last timestamptz; v_created timestamptz;
  v_devices jsonb; v_locations jsonb;
begin
  select nickname, email, coalesce(is_registered,false), ip_address,
         last_seen, created_at
    into v_nick, v_email, v_reg, v_ip, v_last, v_created
    from profiles where id = p_uid;

  -- Snapshot device terakhir milik user (sebelum user_devices dihapus).
  select brand, model into v_brand, v_model
    from user_devices
   where user_id = p_uid
   order by last_seen_at desc nulls last
   limit 1;

  -- Arsip SEMUA device user (biasanya <10; cap 50 anti-bloat).
  select coalesce(jsonb_agg(s.obj order by s.seen desc nulls last), '[]'::jsonb)
    into v_devices
    from (
      select jsonb_build_object(
        'install_id', d.install_id,
        'brand', d.brand,
        'model', d.model,
        'os_name', d.os_name,
        'os_version', d.os_version,
        'app_version', d.app_version,
        'ip_address', d.ip_address,
        'last_seen_at', d.last_seen_at,
        'nickname_snapshot', d.nickname_snapshot,
        'is_active', d.is_active
      ) as obj,
      d.last_seen_at as seen
      from public.user_devices d
      where d.user_id = p_uid
      order by d.last_seen_at desc nulls last
      limit 50
    ) s;

  -- Arsip riwayat GPS/IP terakhir (cap 100 terbaru; cukup untuk audit admin).
  select coalesce(jsonb_agg(s.obj order by s.at desc), '[]'::jsonb)
    into v_locations
    from (
      select jsonb_build_object(
        'lat', h.lat,
        'lon', h.lon,
        'source', h.loc_source,
        'at', h.created_at
      ) as obj,
      h.created_at as at
      from public.user_location_history h
      where h.user_id = p_uid
      order by h.created_at desc
      limit 100
    ) s;

  insert into public.deleted_users
    (user_id, nickname, email, is_registered, brand, model, ip_address,
     last_seen_at, created_at, deleted_at, reason, claimed_by, claimed_nick,
     devices, locations)
  values
    (p_uid, coalesce(v_nick,''), v_email, coalesce(v_reg,false),
     coalesce(v_brand,''), coalesce(v_model,''), coalesce(v_ip,''),
     v_last, v_created, now(),
     p_reason, p_claimed_by, p_claimed_nick,
     coalesce(v_devices,'[]'::jsonb), coalesce(v_locations,'[]'::jsonb))
  on conflict (user_id) do nothing;
end;
$fn$;

-- -- 3. admin_deleted_device_history: utamakan snapshot arsip, fallback live --
create or replace function public.admin_deleted_device_history(p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  v_arch jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  -- Snapshot arsip terbaru untuk nickname ini (hasil hapus baru).
  select d.devices into v_arch
    from public.deleted_users d
   where d.nickname = p_nickname
   order by d.deleted_at desc
   limit 1;
  if v_arch is not null and jsonb_array_length(coalesce(v_arch,'[]'::jsonb)) > 0 then
    return v_arch;
  end if;
  -- Fallback: baris live yatim (arsip lama sebelum kolom devices ada).
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'install_id', d.install_id,
      'brand', d.brand,
      'model', d.model,
      'os_name', d.os_name,
      'os_version', d.os_version,
      'app_version', d.app_version,
      'ip_address', d.ip_address,
      'last_seen_at', d.last_seen_at,
      'nickname_snapshot', d.nickname_snapshot,
      'is_active', d.is_active
    ) order by d.last_seen_at desc nulls last
  ), '[]'::jsonb) into result
  from public.user_devices d
  where d.nickname_snapshot = p_nickname;
  return result;
end;
$function$;

revoke execute on function public.admin_deleted_device_history(text) from public, anon;
grant execute on function public.admin_deleted_device_history(text) to authenticated, service_role;

-- -- 4. admin_deleted_location_history: riwayat GPS/IP user terhapus (dari arsip) --
create or replace function public.admin_deleted_location_history(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(d.locations,'[]'::jsonb) into result
    from public.deleted_users d
   where d.user_id = p_user_id
   limit 1;
  if result is null then
    result := '[]'::jsonb;
  end if;
  return result;
end;
$function$;

revoke execute on function public.admin_deleted_location_history(uuid) from public, anon;
grant execute on function public.admin_deleted_location_history(uuid) to authenticated, service_role;

-- -- 5. admin_list_deleted: sertakan jumlah device & lokasi arsip --
create or replace function public.admin_list_deleted(
  p_limit integer default 100,
  p_offset integer default 0,
  p_include_pending boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (
      select count(*) from public.deleted_users
    ) + case when p_include_pending then (
      -- Anon yang belum dihapus & bukan dummy = "pending" (nickname masih
      -- terpakai, bisa dibebaskan admin).
      select count(*) from public.profiles p
       where coalesce(p.is_registered, false) = false
         and not exists (
           select 1 from public.dummy_accounts d where d.uid = p.id
         )
    ) else 0 end,
    'items', coalesce((
      select jsonb_agg(sub.obj order by sub.sort_at desc nulls last)
      from (
        -- (a) Arsip user terhapus.
        select
          jsonb_build_object(
            'user_id', d.user_id,
            'nickname', d.nickname,
            'email', d.email,
            'is_registered', d.is_registered,
            'brand', d.brand,
            'model', d.model,
            'ip_address', d.ip_address,
            'last_seen_at', d.last_seen_at,
            'created_at', d.created_at,
            'deleted_at', d.deleted_at,
            'reason', d.reason,
            'claimed_by', d.claimed_by,
            'claimed_nick', d.claimed_nick,
            'pending', false,
            'device_count', coalesce(jsonb_array_length(d.devices), 0),
            'location_count', coalesce(jsonb_array_length(d.locations), 0)
          ) as obj,
          d.deleted_at as sort_at
        from public.deleted_users d

        union all

        -- (b) Anon belum dihapus (pending) — hanya bila diminta.
        select
          jsonb_build_object(
            'user_id', p.id,
            'nickname', p.nickname,
            'email', p.email,
            'is_registered', coalesce(p.is_registered, false),
            'brand', '',
            'model', '',
            'ip_address', coalesce(p.ip_address, ''),
            'last_seen_at', p.last_seen,
            'created_at', p.created_at,
            'deleted_at', null,
            'reason', 'pending_anon',
            'claimed_by', null,
            'claimed_nick', null,
            'pending', true,
            'status', p.status,
            'country', p.country,
            'city', p.city,
            'device_count', 0,
            'location_count', 0
          ) as obj,
          -- Urut memakai last_seen agar anon terbaru tampil di atas.
          p.last_seen as sort_at
        from public.profiles p
        where p_include_pending
          and coalesce(p.is_registered, false) = false
          and not exists (
            select 1 from public.dummy_accounts d where d.uid = p.id
          )
      ) sub
      limit greatest(p_limit, 1) offset greatest(p_offset, 0)
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_list_deleted(integer,integer,boolean)
  from public, anon;
grant execute on function public.admin_list_deleted(integer,integer,boolean)
  to authenticated, service_role;
