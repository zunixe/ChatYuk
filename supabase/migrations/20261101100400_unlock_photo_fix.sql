-- ============================================================
-- 20261101100400_unlock_photo_fix.sql
-- unlock_photo versi text (20261031110005) membandingkan parameter `text`
-- dengan kolom `user_photos.id` yang bertipe `uuid`. Postgres tidak punya
-- operator uuid = text → fungsi gagal runtime (42883) saat dipanggil.
-- Versi lama (uuid) masih ter-grant ke authenticated dan MASIH menerima
-- bucket `bonus` (koin gratis) → jalur pencucian bonus ke income owner.
--
-- Perbaikan:
--   • versi text di-cast ke uuid (parse aman), wajib koin beli
--     (topup+earned), idempoten via photo_unlocks, tidak bisa unlock foto
--     sendiri;
--   • versi uuid dicabut dari authenticated (hanya definer/service_role),
--     supaya hanya SATU overload yang bisa dipanggil client.
-- ============================================================

CREATE OR REPLACE FUNCTION public.unlock_photo(p_photo_id text, p_mode text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  points_on boolean; once_cost int; perm_cost int; owner_pct int;
  cost int; owner_id uuid; owner_share int; remaining int;
  paid int; topup_avail int;
  take_topup int; take_earned int;
  v_photo uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_mode not in ('once','perm') then raise exception 'Invalid mode'; end if;

  -- Parameter datang sebagai text dari PostgREST → cast eksplisit.
  begin
    v_photo := trim(p_photo_id)::uuid;
  exception when others then
    raise exception 'Invalid photo id';
  end;

  select points_enabled, photo_unlock_once, photo_unlock_perm, photo_unlock_owner_pct
    into points_on, once_cost, perm_cost, owner_pct
    from app_settings where id = 'global';

  if points_on is false then
    return jsonb_build_object('ok', true, 'tier', 'free', 'points',
      (select points from public.profiles where id = me));
  end if;

  select user_id into owner_id from public.user_photos where id = v_photo;
  if owner_id is null then
    raise exception 'Photo not found';
  end if;
  if owner_id = me then
    return jsonb_build_object('ok', true, 'tier', 'free', 'points',
      (select points from public.profiles where id = me));
  end if;

  -- Idempoten: sudah pernah dibuka permanen → jangan menagih lagi.
  if exists (select 1 from public.photo_unlocks
              where viewer_id = me and photo_id = v_photo) then
    return jsonb_build_object('ok', true, 'tier', 'owned', 'points',
      (select points from public.profiles where id = me));
  end if;

  cost := case when p_mode = 'perm' then coalesce(perm_cost,20)
               else coalesce(once_cost,5) end;

  -- WAJIB koin beli/penghasilan. `bonus` gratis tidak boleh.
  select coalesce(sum(amount) filter (where bucket='topup'), 0),
         coalesce(sum(amount) filter (where bucket='topup'), 0)
       + coalesce(sum(amount) filter (where bucket='earned'), 0)
    into topup_avail, paid
    from public.coin_ledger where user_id = me;

  if paid < cost then
    raise exception 'Not enough points';
  end if;

  -- Serialisasi per user (cegah dua unlock paralel menagih dua kali).
  perform pg_advisory_xact_lock(hashtext('wallet:' || me::text));

  take_topup := least(topup_avail, cost);
  take_earned := cost - take_topup;

  if take_topup > 0 then
    insert into public.coin_ledger(user_id,bucket,type,amount,ref_id)
      values (me,'topup','photo_unlock',-take_topup,v_photo::text);
  end if;
  if take_earned > 0 then
    insert into public.coin_ledger(user_id,bucket,type,amount,ref_id)
      values (me,'earned','photo_unlock',-take_earned,v_photo::text);
  end if;

  remaining := public.wallet_sync_points(me);

  owner_share := (cost * owner_pct) / 100;
  if owner_share > 0 then
    perform public.ledger_credit(owner_id, 'earned', 'photo_income',
      owner_share, v_photo::text,
      jsonb_build_object('from', me, 'mode', p_mode, 'gross', cost));
  end if;

  insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
    values ('photo_unlock', cost - owner_share, me, owner_id, v_photo::text,
            jsonb_build_object('mode', p_mode, 'gross', cost,
                               'owner_share', owner_share));

  insert into public.point_events (user_id, event, amount, metadata)
    values (me, 'photo_unlock', -cost,
            jsonb_build_object('photo_id', v_photo, 'mode', p_mode));

  if p_mode = 'perm' then
    insert into public.photo_unlocks (viewer_id, photo_id) values (me, v_photo)
      on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'tier', 'paid', 'points', remaining,
    'owner_share', owner_share);
end;
$function$;

-- Grants: hanya overload text yang bisa dipanggil client.
REVOKE EXECUTE ON FUNCTION public.unlock_photo(text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.unlock_photo(text, text) TO authenticated, service_role;

-- Overload lama (uuid) masih menerima bucket `bonus` → cabut akses client.
-- SAFE: tidak ada pemanggil client yang memakai signature uuid
-- (PointsService.unlockPhoto mengirim string; UI unlock belum dipakai).
-- Terdampak bila salah: fitur buka foto — hanya lewat overload text.
REVOKE EXECUTE ON FUNCTION public.unlock_photo(uuid, text) FROM public, anon, authenticated;
