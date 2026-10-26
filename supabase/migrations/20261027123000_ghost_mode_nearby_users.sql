-- ============================================================
-- LENGKAPI ghost mode: tutup jalur bocor TERAKHIR — `nearby_users`.
--
-- Audit (2026-10-26) membandingkan semua RPC yang membawa `status`:
--
--   RPC                      privacy  cek ghost
--   get_online_users           ya        ya   (20261027121000)
--   presence_for               ya        ya   (20261027121000)
--   profile_public             ya        ya   (20261027122000)
--   nearby_users               ya     **TIDAK**  ← ditutup di sini
--
-- `nearby_users` memakai filter presence yang sama dengan get_online_users
-- (`status in ('online','idle')` + `privacy_can_view('presence')`) tetapi
-- tidak memeriksa `ghost_mode_active`. Jadi user yang membayar Ghost Mode
-- tetap terlihat di daftar "Nearby" walau sudah hilang dari daftar Online.
--
-- Perbaikan minimal: tambah satu klausa `not exists (ghost_mode_active)`.
-- Signature, urutan kolom, harga/gating YukCoin, dan filter lain TIDAK
-- berubah (CREATE OR REPLACE dari definisi live, bukan ditulis ulang).
--
-- CARA APPLY: Management API / SQL editor (CLI db push HANG di Mac ini).
-- ROLLBACK: hapus klausa ghost (kembalikan definisi sebelumnya).
-- ============================================================

CREATE OR REPLACE FUNCTION public.nearby_users(p_radius_km double precision DEFAULT 10, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(uid uuid, nickname text, gender text, age integer, country text, city text, status text, avatar text, is_registered boolean, last_seen timestamp with time zone, distance_km double precision)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- GHOST MODE: user yang membeli invisible tidak boleh muncul di Nearby.
    and not exists (
      select 1 from public.ghost_mode_active g
      where g.user_id = p.id and g.expires_at > now()
    )
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
$function$
