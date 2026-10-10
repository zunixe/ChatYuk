-- ============================================================
-- ChatYuk: Fase 4 — paginasi (offset) untuk social_list & nearby_users.
--
-- Sebelumnya:
--   - social_list(p_kind,p_user,p_limit) : tanpa offset → daftar >limit
--     tak bisa dimuat bertahap (Fase 1 kirim limit 200 sbg mitigasi).
--   - nearby_users(p_radius_km) : `limit 100` HARDCODE, tanpa offset.
--
-- Sekarang: tambah p_offset (default 0) → load-more server-side.
-- Overload lama DI-DROP agar tidak ambigu; pemanggil lama (tanpa offset)
-- tetap jalan karena p_offset punya DEFAULT 0.
--
-- Logika inti TIDAK diubah (hanya tambah offset untuk paging).
-- ============================================================
-- menyentuh: nearby_users
--
-- nearby_users FROZEN: signature + p_limit/p_offset (overload lama
-- `nearby_users(double precision)` DI-DROP). Snapshot sudah
-- di-regenerate (scripts/snapshot_functions.sh) — cabang kritis
-- (dummy/visibility) tak berubah, hanya penambahan paging.
-- ============================================================

-- ── social_list: + p_offset ──
drop function if exists public.social_list(text, uuid, integer);
create or replace function public.social_list(
  p_kind text,
  p_user uuid DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  res jsonb;
  target uuid := coalesce(p_user, auth.uid());
  v_me uuid := auth.uid();
  lim int := greatest(1, least(p_limit, 200));
  off int := greatest(0, coalesce(p_offset, 0));
begin
  if p_kind = 'followers' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.follower_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, f.created_at
      from follows f join profiles p on p.id = f.follower_id
      where f.followee_id = target
      order by f.created_at desc
      limit lim offset off
    ) x;
  elsif p_kind = 'following' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.followee_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, f.created_at
      from follows f join profiles p on p.id = f.followee_id
      where f.follower_id = target
      order by f.created_at desc
      limit lim offset off
    ) x;
  elsif p_kind = 'friends' then
    select coalesce(jsonb_agg(x order by x.nickname), '[]'::jsonb) into res
    from (
      select p.id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered
      from follows a join follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join profiles p on p.id = a.followee_id
      where a.follower_id = target and p.id <> target
      order by p.nickname
      limit lim offset off
    ) x;
  elsif p_kind = 'subscribers' then
    select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
    from (
      select s.subscriber_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, s.expires_at
      from subscriptions s join profiles p on p.id = s.subscriber_id
      where s.creator_id = target and s.expires_at > now()
      order by s.expires_at desc
      limit lim offset off
    ) x;
  else
    raise exception 'Invalid kind';
  end if;
  return coalesce(res, '[]'::jsonb);
end;
$function$;

revoke execute on function public.social_list(text, uuid, integer, integer) from public, anon;
grant execute on function public.social_list(text, uuid, integer, integer) to authenticated;

-- ── nearby_users: + p_limit/p_offset (sebelumnya LIMIT 100 hardcode) ──
drop function if exists public.nearby_users(double precision);
create or replace function public.nearby_users(
  p_radius_km double precision DEFAULT 10,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
returns table(
  uid uuid, nickname text, gender text, age integer, country text,
  city text, status text, avatar text, is_registered boolean,
  last_seen timestamp with time zone, distance_km double precision
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  radius_m double precision;
  v_excl uuid[];
  v_price int;
  v_published boolean;
  v_admin boolean;
  v_today date;
  v_paid int;
  lim int := greatest(1, least(p_limit, 200));
  off int := greatest(0, coalesce(p_offset, 0));
begin
  if me is null then raise exception 'Not authenticated'; end if;

  v_admin := coalesce(auth.email(), '') = 'zunixe@gmail.com';
  select (feature_flags -> 'nearby_paid' ->> 'published')::boolean,
         coalesce(nearby_cost, 25)
    into v_published, v_price
    from app_settings where id = 'global';

  if coalesce(v_published, false) and not v_admin then
    v_today := (now() at time zone 'Asia/Jakarta')::date;
    select count(*) into v_paid from public.yukcoin_consumptions
      where user_id = me and feature = 'nearby'
        and ref_id = 'nearby:' || v_today::text;
    if v_paid = 0 then
      perform public.gate_feature('nearby', 'nearby');
    end if;
  end if;

  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon
    into my_lat, my_lon
  from public.profiles p where p.id = me;

  if my_lat is null or my_lon is null then
    raise exception 'No location';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  return query
  select
    p.id,
    p.nickname,
    p.gender,
    p.age,
    p.country,
    p.city,
    p.status,
    case when public.privacy_can_view(p.id, 'profile_photo', me) then p.avatar else '' end,
    p.is_registered,
    case when public.privacy_can_view(p.id, 'last_seen', me) then p.last_seen else null end,
    (earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) / 1000.0) as distance_km
  from public.profiles p
  where p.id <> me
    and p.lat is not null
    and p.lon is not null
    and p.status in ('online', 'idle')
    and p.last_seen >= now() - interval '30 minutes'
    and public.privacy_can_view(p.id, 'presence', me)
    and not (p.id = any(v_excl))
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    )
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by 11 asc
  limit lim offset off;
end;
$function$;

revoke execute on function public.nearby_users(double precision, integer, integer) from public, anon;
grant execute on function public.nearby_users(double precision, integer, integer) to authenticated;
