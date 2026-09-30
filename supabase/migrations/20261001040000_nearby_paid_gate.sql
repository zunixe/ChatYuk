-- ============================================================
-- ChatYuk — Gate "Orang Sekitar" (nearby) berbayar harian
--
-- Fitur "Orang Sekitar" jadi berbayar: sekali bayar per hari (coin), bebas
-- seharian. Gate di SERVER (sumber kebenaran) — bukan hanya client.
--
-- Aturan produk: harga = app_settings.nearby_cost, idempoten per hari via
-- yukcoin_consumptions (ref = 'nearby:<tanggal>'). Bila fitur BELUM
-- dipublish (feature_flags.nearby_paid.published=false) & pemanggil bukan
-- admin → GRATIS (perilaku lama, supaya build user tidak rusak sebelum
-- publish).
--
-- Fungsi FROZEN: nearby_users → header '-- menyentuh:' WAJIB.
-- Basis: snapshot terbaru (20260928100000_nearby_show_all_with_location.sql)
-- + tambah gate biaya di awal fungsi. Idempotent (create or replace).
-- ============================================================

-- menyentuh: nearby_users
create or replace function public.nearby_users(p_radius_km double precision default 10)
 returns table(uid uuid, nickname text, gender text, age integer, country text, city text,
   status text, avatar text, is_registered boolean, last_seen timestamptz, distance_km double precision)
 language plpgsql
 security definer
 set search_path to 'public'
as $fn$
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
begin
  if me is null then raise exception 'Not authenticated'; end if;

  -- ── Gate biaya (harian) — hanya bila fitur sudah dipublish ──
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
      -- Belum bayar hari ini → tagih. Raise 'YukCoin tidak cukup' bila kurang
      -- (client menangkap & tampilkan dialog topup).
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
  limit 100;
end;
$fn$;

revoke execute on function public.nearby_users(double precision) from public, anon;
grant execute on function public.nearby_users(double precision) to authenticated;
