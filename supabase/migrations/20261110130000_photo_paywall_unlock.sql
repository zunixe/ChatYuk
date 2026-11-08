-- menyentuh: get_user_photos_access, unlock_photo, metered_pricing_public
-- Paywall foto profil v2 (reaktivasi unlock_photo yang dicabut 2026-11-01):
--
--   • Viewer profil FEMALE: 4 foto pertama gratis, sisanya blur + kunci.
--     Buka permanen per foto: photo_unlock_perm koin (di-set 15 di sini).
--   • Viewer profil male / dirinya sendiri / points off → semua terbuka
--     (perilaku lama).
--   • HANYA koin berbayar (topup+earned) — bonus tidak bisa (spec: "coin
--     berbayar"). Pakai ledger_spend_paid, bukan ledger_spend_dual.
--   • Pemilik foto dapat photo_unlock_owner_pct% ke bucket 'earned'
--     (photo_income) — insentif upload; sisanya platform_revenue.
--   • Harga & persen tetap admin-configurable via app_settings (kolom
--     photo_unlock_perm / photo_unlock_owner_pct sudah ada).
--
-- Mode 'once' dibuang: hanya 'perm' (unlock sekali = lihat selamanya).
-- Overload unlock_photo(text,text) tetap dicabut (legacy).

-- ── 1. get_user_photos_access: idx<4 gratis + gate gender PEMILIK ──
create or replace function public.get_user_photos_access(p_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  points_on boolean;
  owner_female boolean;
  arr jsonb := '[]'::jsonb;
  rec record;
  idx int := 0;
  is_unlocked boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  select gender = 'female' into owner_female
    from profiles where id = p_user_id;

  for rec in
    select id, photo, photo_preview, created_at
    from user_photos where user_id = p_user_id
    order by created_at asc
  loop
    -- Terbuka: koin mati / foto sendiri / profil non-female (paywall hanya
    -- untuk foto milik female) / 4 pertama / sudah beli permanen.
    is_unlocked := (points_on is false)
                or (me = p_user_id)
                or (owner_female is not true)
                or (idx < 4)
                or exists (select 1 from photo_unlocks
                           where viewer_id = me and photo_id = rec.id);

    arr := arr || jsonb_build_object(
      'id', rec.id,
      'unlocked', is_unlocked,
      -- Foto asli hanya dikirim bila terbuka; jika terkunci kirim preview blur.
      'photo', case when is_unlocked then rec.photo else coalesce(rec.photo_preview, '') end,
      'preview', coalesce(rec.photo_preview, ''),
      'created_at', rec.created_at
    );
    idx := idx + 1;
  end loop;

  return arr;
end; $function$;

-- ── 2. unlock_photo: paid-only, permanen, owner share ──
create or replace function public.unlock_photo(p_photo_id uuid, p_mode text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  points_on boolean; perm_cost int; owner_pct int;
  owner_id uuid; owner_share int; remaining int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_mode <> 'perm' then raise exception 'Invalid mode'; end if;

  select points_enabled, photo_unlock_perm, photo_unlock_owner_pct
    into points_on, perm_cost, owner_pct
    from app_settings where id = 'global';

  select user_id into owner_id from user_photos where id = p_photo_id;
  if owner_id is null then raise exception 'Photo not found'; end if;
  if owner_id = me or points_on is false then
    return jsonb_build_object('ok', true, 'remaining',
      (select points from profiles where id = me));
  end if;
  -- Idempoten: sudah dibuka → gratis (tidak tagih ulang).
  if exists (select 1 from photo_unlocks
             where viewer_id = me and photo_id = p_photo_id) then
    return jsonb_build_object('ok', true, 'remaining',
      (select points from profiles where id = me));
  end if;

  -- HANYA koin berbayar (topup+earned). Bonus tidak bisa → raise 'Not
  -- enough paid' bila saldo kurang.
  remaining := public.ledger_spend_paid(me, 'photo_unlock', perm_cost, p_photo_id::text);

  owner_share := (perm_cost * owner_pct) / 100;
  if owner_share > 0 then
    perform public.ledger_credit(owner_id, 'earned', 'photo_income',
      owner_share, p_photo_id::text,
      jsonb_build_object('viewer', me));
  end if;
  insert into platform_revenue (source, amount, metadata)
    values ('photo_unlock', perm_cost - owner_share,
            jsonb_build_object('photo_id', p_photo_id, 'viewer', me, 'owner', owner_id));
  insert into point_events (user_id, event, amount, metadata)
    values (me, 'photo_unlock', -perm_cost, jsonb_build_object('photo_id', p_photo_id));
  insert into photo_unlocks (viewer_id, photo_id) values (me, p_photo_id)
    on conflict do nothing;

  return jsonb_build_object('ok', true, 'remaining', remaining);
end; $function$;

grant execute on function public.unlock_photo(uuid, text) to authenticated;

-- ── 3. metered_pricing_public: expose harga unlock ke client ──
create or replace function public.metered_pricing_public()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  return (select jsonb_build_object(
    'call_audio_cost_per_min', call_audio_cost_per_min,
    'call_video_cost_per_min', call_video_cost_per_min,
    'call_free_minutes_daily', call_free_minutes_daily,
    'filter_gender_cost', filter_gender_cost,
    'nearby_cost', nearby_cost,
    -- == v_fee di random_match_join (fee pencarian saat pasangan terbentuk).
    'match_search_cost', 2,
    'match_connect_cost',
      coalesce((metered_pricing->'match_call'->>'unit_cost')::int, 10),
    'match_free_seconds', 30,
    'photo_unlock_cost', photo_unlock_perm
  ) from app_settings where id = 'global');
end; $function$;

-- ── 4. Harga default: 15 koin/foto (keputusan 2026-11-08). ──
update app_settings set photo_unlock_perm = 15 where id = 'global';
