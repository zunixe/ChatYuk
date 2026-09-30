-- ============================================================
-- Deteksi Fake GPS — flag device (Position.isMocked) + heuristik server.
-- Hanya MENANDAI (badge admin); TIDAK memblokir/menyembunyikan user.
--
-- 1) profiles: + location_mocked / location_mock_reason /
--    location_flagged_at / location_accuracy_m.
-- 2) user_location_history: + location_mocked / mock_reason / accuracy_m
--    (riwayat flag, untuk audit admin).
-- 3) update_my_location 4-arg → 6-arg (+p_mocked, +p_accuracy) +
--    heuristik: is_mocked | impossible_speed | accuracy_zero | spoof_delta.
--    Overload lama DI-DROP (cegah RPC ambiguous).
-- 4) admin_stats_detail: + location_mocked / mock_reason di 4 query users_*.
-- 5) admin_user_detail: location_history + mocked / reason / accuracy_m.
--
-- SUMBER: update_my_location, admin_stats_detail (LIVE), admin_user_detail
--   (LIVE) — badan disalin persis, hanya penambahan.
--
-- menyentuh: admin_stats_detail
--
-- CARA APPLY: Management API (CLI db push HANG).
-- ROLLBACK: re-apply update_my_location 4-arg @20260815150000,
--   admin_stats_detail @20260928070000, admin_user_detail (live), drop kolom.
-- ============================================================

-- ── 1) Kolom profiles ──
alter table public.profiles
  add column if not exists location_mocked boolean not null default false,
  add column if not exists location_mock_reason text,
  add column if not exists location_flagged_at timestamptz,
  add column if not exists location_accuracy_m integer;

-- ── 2) Kolom history ──
alter table public.user_location_history
  add column if not exists location_mocked boolean not null default false,
  add column if not exists mock_reason text,
  add column if not exists accuracy_m integer;

-- ── 3) update_my_location: 4-arg → 6-arg + heuristik ──
drop function if exists public.update_my_location(double precision, double precision, text, text);

create or replace function public.update_my_location(
  p_lat double precision,
  p_lon double precision,
  p_source text,
  p_ip text default null,
  p_mocked boolean default false,
  p_accuracy integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  uid uuid := auth.uid();
  v_ip text := nullif(trim(coalesce(p_ip, '')), '');
  v_last_lat double precision;
  v_last_lon double precision;
  v_last_at timestamptz;
  v_reason text := null;
  v_flag boolean := false;
  v_speed_mps double precision;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;

  -- Heuristik (hanya relevan untuk source gps; IP = perkiraan, tak dinilai).
  if p_source = 'gps' then
    -- (a) device melaporkan mock provider.
    if coalesce(p_mocked, false) then
      v_flag := true; v_reason := 'is_mocked';
    end if;
    -- (b) akurasi 0 / negatif persis (khas mock).
    if p_accuracy is not null and p_accuracy <= 0 then
      v_flag := true;
      v_reason := case when v_reason is null then 'accuracy_zero'
                       else v_reason || ',accuracy_zero' end;
    end if;
    -- (c) kecepatan mustahil (>250 m/s ≈ 900 km/jam) dari titik terakhir.
    --     Butuh jeda ≥10 dtk antar update — kalau tidak, dua update cepat
    --     (mis. app kirim ulang) bisa salah dianggap lompatan mustahil.
    select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
      from public.user_location_history
     where user_id = uid
     order by created_at desc limit 1;
    if found and v_last_at is not null
       and now() - v_last_at >= interval '10 seconds' then
      v_speed_mps := earth_distance(
        ll_to_earth(v_last_lat, v_last_lon), ll_to_earth(p_lat, p_lon))
        / extract(epoch from (now() - v_last_at));
      if v_speed_mps > 250 then
        v_flag := true;
        v_reason := case when v_reason is null then 'impossible_speed'
                         else v_reason || ',impossible_speed' end;
      end if;
    end if;
    -- (d) GPS vs IP terakhir berbeda > 500 km (spoof).
    if exists (
      select 1 from public.profiles
      where id = uid and lat_ip is not null and lon_ip is not null)
    then
      if (
        select earth_distance(ll_to_earth(lat_ip, lon_ip), ll_to_earth(p_lat, p_lon))
        from public.profiles where id = uid) > 500000 then
        v_flag := true;
        v_reason := case when v_reason is null then 'spoof_delta'
                         else v_reason || ',spoof_delta' end;
      end if;
    end if;
  end if;

  if p_source = 'gps' then
    update public.profiles
       set lat_gps        = p_lat,
           lon_gps        = p_lon,
           gps_updated_at = now(),
           lat            = p_lat,
           lon            = p_lon,
           loc_source     = 'gps',
           loc_updated_at = now(),
           location_mocked      = v_flag,
           location_mock_reason = v_reason,
           location_accuracy_m  = p_accuracy,
           location_flagged_at  = case when v_flag then now()
                                       else location_flagged_at end
     where id = uid;
  else
    update public.profiles
       set lat_ip        = p_lat,
           lon_ip        = p_lon,
           ip_updated_at = now(),
           ip_address    = coalesce(v_ip, ip_address),
           lat           = coalesce(lat_gps, p_lat),
           lon           = coalesce(lon_gps, p_lon),
           loc_source    = case when lat_gps is not null then 'gps' else 'ip' end,
           loc_updated_at = now()
     where id = uid;
  end if;

  -- History: lewati bila diam (<50m) & titik terakhir masih segar (<30 mnt),
  -- TAPI tetap catat bila ada flag mock (agar riwayat audit tak bolong).
  select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
    from public.user_location_history
   where user_id = uid
   order by created_at desc limit 1;
  if found
     and earth_distance(
           ll_to_earth(v_last_lat, v_last_lon),
           ll_to_earth(p_lat, p_lon)) < 50
     and now() - v_last_at < interval '30 minutes'
     and not v_flag then
    return;
  end if;
  insert into public.user_location_history
    (user_id, lat, lon, loc_source, location_mocked, mock_reason, accuracy_m)
  values (uid, p_lat, p_lon, p_source, v_flag, v_reason, p_accuracy);
end;
$fn$;

revoke execute on function public.update_my_location(double precision, double precision, text, text, boolean, integer) from public, anon;
grant execute on function public.update_my_location(double precision, double precision, text, text, boolean, integer) to authenticated;

-- ── 4) admin_stats_detail: + location_mocked / mock_reason (LIVE @20260928070000) ──
create or replace function public.admin_stats_detail()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_dummy))), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last)
      from profiles where is_registered = true
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles where is_registered = false
        and not (id = any(v_dummy))), '[]'::jsonb),
    'rooms_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'room_id', t.room_id,
        'room_name', coalesce(r.name, t.room_id),
        'is_private', coalesce(r.is_private, false),
        'user_count', t.c
      ) order by t.c desc)
      from (select room_id, count(*) as c from room_presence group by room_id) t
      left join rooms r on r.id = t.room_id), '[]'::jsonb),
    'messages_today', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'sender_id', sender_id,
          'sender_name', sender_name,
          'sender_gender', sender_gender,
          'text', case when type = 'image' then '[foto]' else text end,
          'type', type,
          'created_at', created_at
        ) as x
        from private_messages
        where created_at >= current_date at time zone 'Asia/Jakarta'
        order by created_at desc
        limit 200
      ) sub), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

-- ── 5) admin_user_detail: location_history + mocked/reason/accuracy (LIVE) ──
create or replace function public.admin_user_detail(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id',        pr.id,
      'nickname',       pr.nickname,
      'gender',         pr.gender,
      'age',            pr.age,
      'country',        pr.country,
      'city',           pr.city,
      'email',          pr.email,
      'is_registered',  pr.is_registered,
      'status',         pr.status,
      'points',         pr.points,
      'ip_address',     pr.ip_address,
      'login_at',       pr.login_at,
      'last_seen',      pr.last_seen,
      'created_at',     pr.created_at,
      'is_dummy',       exists (select 1 from public.dummy_accounts du where du.uid = pr.id)
    ),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
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
      ) order by d.last_seen_at desc nulls last)
      from public.user_devices d where d.user_id = p_uid
    ), '[]'::jsonb),
    'chats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'chat_id', c.chat_id,
        'participant_names', c.participant_names,
        'participants', c.participants,
        'last_message', c.last_message,
        'last_message_at', c.last_message_at,
        'message_count', coalesce(m.msg_count, 0)
      ) order by c.last_message_at desc nulls last)
      from public.private_chats c
      -- SATU agregasi (ganti count(*) per chat).
      left join (
        select m.chat_id as chat_id, count(*) as msg_count
          from public.private_messages m
         where m.chat_id in (
           select c2.chat_id from public.private_chats c2
           where c2.participants @> array[p_uid]::uuid[]
         )
         group by m.chat_id
      ) m on m.chat_id = c.chat_id
      where c.participants @> array[p_uid]::uuid[]
    ), '[]'::jsonb),
    -- DIBATASI 200 terbaru (dulu tanpa limit).
    'location_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lat', h.lat,
        'lon', h.lon,
        'source', h.loc_source,
        'at', h.created_at,
        'mocked', h.location_mocked,
        'reason', h.mock_reason,
        'accuracy_m', h.accuracy_m
      ) order by h.created_at desc)
      from (
        select h2.lat, h2.lon, h2.loc_source, h2.created_at,
               h2.location_mocked, h2.mock_reason, h2.accuracy_m
          from public.user_location_history h2
         where h2.user_id = p_uid
         order by h2.created_at desc
         limit 200
      ) h
    ), '[]'::jsonb)
  ) into result
  from public.profiles pr
  where pr.id = p_uid;

  return result;
end;
$function$;
