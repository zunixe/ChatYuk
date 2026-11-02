-- ══════════════════════════════════════════════════════════════════════
-- Charge-on-match: fee pencarian match dipotong SAAT pair terbentuk,
-- bukan saat klik Match (audit Fase 17 — keluhan user: koin hangus walau
-- tak ketemu siapa pun).
--
-- Perubahan:
--   • _spend_yukcoin_core (BARU, internal): seluruh logika debit
--     spend_yukcoin TANPA auth guard — untuk dipanggil fungsi trusted
--     SECURITY DEFINER (random_match_join menagih partner male saat
--     joiner-nya female; auth guard p_user=auth.uid() akan menolak itu).
--     DIREVOKE dari public/anon/authenticated — hanya service_role &
--     definer.
--   • spend_yukcoin: kini wrapper tipis = auth guard + core.
--   • random_match_join:
--       - male yang jelas tak mampu bayar (yukcoin_total < fee) →
--         status 'no_funds', TIDAK masuk antrean;
--       - kandidat partner male tak mampu bayar → diskip (precheck);
--       - fee ditagih via _spend_yukcoin_core TEPAT sebelum pair dibuat
--         (payer = pihak male; female gratis; points_enabled OFF →
--         free-pass otomatis). Gagal/race → kandidat berikutnya;
--       - jika payer adalah joiner sendiri dan gagal → baris antreannya
--         dihapus + 'no_funds'.
--   Semantik tetap: 1 transaksi atomik — kalau pair gagal dibuat setelah
--   tagih, debit ikut rollback.
-- Client: provider tidak charge duluan; status 'no_funds' → dialog koin
-- (MATCH_NEED_COIN yang sudah ada).
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. _spend_yukcoin_core — inti debit (internal, tanpa auth gate) ────
CREATE OR REPLACE FUNCTION public._spend_yukcoin_core(p_user uuid, p_feature text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e int; b int; need int; take int; tier text;
begin
  -- INTERNAL ONLY — dipanggil dari fungsi trusted SECURITY DEFINER
  -- (mis. random_match_join). Auth gate ada di wrapper spend_yukcoin.
  -- REVOKE dari public/anon/authenticated di bagian grant.
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  -- Kill-switch ekonomi: points_enabled=false → free (pola 110013).
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  -- 2026-10-31: hanya GIFT + biaya pencarian MATCH yang memotong poin.
  -- undo, edit, slot foto, mode hantu, filter, nearby → GRATIS.
  if p_feature not in ('gift','gift_sent','match_search') then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  -- Audit: female tidak pernah keluar koin.
  if p_feature = 'match_search'
     and (select gender from public.profiles where id = p_user) = 'female' then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = p_user;

  if (e + b) < p_amount then
    raise exception 'YukCoin tidak cukup';
  end if;

  need := p_amount;
  take := least(e, need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (p_user, 'earned', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
    need := need - take;
  end if;
  if need > 0 then
    take := least(b, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
  end if;

  tier := case when e >= p_amount then 'earned' else 'mixed' end;

  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (p_user, p_feature, p_amount, p_ref, coalesce(p_meta, '{}'::jsonb));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, p_feature, -p_amount,
            jsonb_build_object('feature', p_feature, 'ref', p_ref, 'tier', tier));

  -- Audit: fee pencarian match hangus (tidak ada penerima) → revenue platform.
  if p_feature = 'match_search' then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('match_search', p_amount, p_user, null, p_ref,
              jsonb_build_object('kind', 'search_fee'));
  end if;

  return jsonb_build_object('tier', tier, 'charged', p_amount,
    'remaining', public.yukcoin_total(p_user));
end;
$function$;

-- ── 2. spend_yukcoin — wrapper: auth guard + core ──────────────────────
CREATE OR REPLACE FUNCTION public.spend_yukcoin(p_user uuid, p_feature text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null and p_user is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh mendebit saldo user lain'
      using errcode = '42501';
  end if;
  return public._spend_yukcoin_core(p_user, p_feature, p_amount, p_ref, p_meta);
end;
$function$;

-- ── 3. random_match_join — charge saat pair terbentuk ──────────────────
CREATE OR REPLACE FUNCTION public.random_match_join(p_want_gender text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_want text;
  v_gender text;
  my_lat double precision;
  my_lon double precision;
  v_registered boolean;
  v_all boolean;
  v_anon boolean;
  q record;
  cid uuid;
  p_name text; p_gender text; p_age int; p_city text; p_avatar text;
  p_dist double precision;
  v_excl uuid[];
  v_payer uuid;
  v_tried uuid[] := '{}'::uuid[];
  v_points_on boolean;
  v_fee int := 2;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;

  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false),
         coalesce(points_enabled, true)
    into v_all, v_anon, v_points_on
    from public.app_settings where id = 'global';
  if not v_all then raise exception 'CALL_DISABLED'; end if;

  select gender, lat, lon, coalesce(is_registered, false)
    into v_gender, my_lat, my_lon, v_registered
    from public.profiles where id = me;
  if not v_anon and not v_registered then
    raise exception 'CALL_REGISTERED_ONLY';
  end if;

  -- 2026-10-31: LAWAN JENIS OTOMATIS. Male → cari female, female → cari male.
  -- Tidak ada pilihan manual "Semua".
  v_want := case v_gender
              when 'male'   then 'female'
              when 'female' then 'male'
              else coalesce(nullif(p_want_gender,''), 'all')
            end;

  if exists (
    select 1 from public.calls c
     where (c.caller_id = me or c.callee_id = me)
       and c.status in ('ringing', 'answered')
       and coalesce(c.last_seen_at, c.answered_at, c.created_at) > now() - interval '5 minutes'
  ) then
    raise exception 'ALREADY_IN_CALL';
  end if;

  -- 2026-10-31 (charge-on-match): fee dipotong SAAT pair terbentuk, bukan
  -- saat klik. Male yang jelas tak mampu bayar tidak masuk antrean.
  if v_gender = 'male' and v_points_on
     and public.yukcoin_total(me) < v_fee then
    return jsonb_build_object('status', 'no_funds');
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  insert into public.random_match_queue
    (user_id, gender, want_gender, lat, lon, pinged_at, matched_call_id, matched_with)
  values (me, v_gender, v_want, my_lat, my_lon, now(), null, null)
  on conflict (user_id) do update
    set gender = excluded.gender,
        want_gender = excluded.want_gender,
        lat = excluded.lat,
        lon = excluded.lon,
        pinged_at = now(),
        matched_call_id = null,
        matched_with = null;

  -- Charge-on-match: loop kandidat → coba tagih pihak male → pair yang
  -- terbayar pertama yang jadi. Kandidat male yang tak mampu bayar diskip
  -- lewat precheck; spend tetap authoritative untuk race (saldo berubah
  -- antara antre dan pair).
  q := null;
  loop
    select rq.* into q
      from public.random_match_queue rq
     where rq.user_id <> me
       and rq.matched_call_id is null
       and rq.pinged_at > now() - interval '30 seconds'
       and (v_want = 'all' or rq.gender = v_want)
       and (rq.want_gender = 'all' or rq.want_gender = v_gender)
       and (rq.gender <> 'male' or not v_points_on
            or public.yukcoin_total(rq.user_id) >= v_fee)
       and not (rq.user_id = any (v_tried))
       and not exists (
         select 1 from public.blocks b
          where (b.blocker_id = me and b.blocked_id = rq.user_id)
             or (b.blocker_id = rq.user_id and b.blocked_id = me)
       )
       and not (rq.user_id = any (v_excl))
       and not exists (
         select 1 from public.ghost_mode_active g
          where g.user_id = rq.user_id and g.expires_at > now()
       )
       and not exists (
         select 1 from public.random_match_pairs rp
          where rp.created_at > now() - interval '10 minutes'
            and ((rp.a = me and rp.b = rq.user_id)
              or (rp.a = rq.user_id and rp.b = me))
       )
     order by
       case when my_lat is not null and rq.lat is not null
            then earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(rq.lat, rq.lon))
            else 1e12 end asc,
       rq.pinged_at asc
     for update skip locked
     limit 1;
    if not found then
      q := null;
      exit;
    end if;

    -- Payer = pihak male (female gratis). Kalau joiner female → partner
    -- male-nya yang membayar lewat fungsi internal (core, tanpa auth gate).
    v_payer := case when v_gender = 'male' then me else q.user_id end;
    begin
      perform public._spend_yukcoin_core(v_payer, 'match_search', v_fee, 'match');
      exit; -- terbayar (atau free-pass saat points_enabled OFF) → pair jadi
    exception when others then
      if v_payer = me then
        delete from public.random_match_queue where user_id = me;
        return jsonb_build_object('status', 'no_funds');
      end if;
      v_tried := v_tried || q.user_id;
      q := null;
    end;
  end loop;

  if q is null then
    return jsonb_build_object('status', 'waiting');
  end if;

  insert into public.calls
    (caller_id, callee_id, call_type, status, kind, answered_at, last_seen_at)
  values (me, q.user_id, 'video', 'answered', 'random', now(), now())
  returning id into cid;

  update public.random_match_queue
     set matched_call_id = cid, matched_with = q.user_id, pinged_at = now()
   where user_id = q.user_id;

  update public.random_match_queue
     set matched_call_id = cid, matched_with = q.user_id, pinged_at = now()
   where user_id = me;

  insert into public.random_match_pairs (a, b)
  values (least(me, q.user_id), greatest(me, q.user_id))
  on conflict do nothing;

  select p.nickname, p.gender, p.age, p.city,
         case when public.privacy_can_view(p.id, 'profile_photo', me)
              then p.avatar else '' end
    into p_name, p_gender, p_age, p_city, p_avatar
    from public.profiles p where p.id = q.user_id;

  if my_lat is not null and q.lat is not null and q.lon is not null then
    p_dist := earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(q.lat, q.lon)) / 1000.0;
  end if;

  return jsonb_build_object(
    'status', 'matched',
    'call_id', cid,
    'is_caller', true,
    'partner', jsonb_build_object(
      'uid', q.user_id,
      'nickname', coalesce(p_name, 'User'),
      'gender', coalesce(p_gender, 'other'),
      'age', p_age,
      'city', p_city,
      'avatar', coalesce(p_avatar, ''),
      'distance_km', p_dist
    )
  );
end;
$function$;

-- ── Grants ───────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public._spend_yukcoin_core(uuid, text, int, text, jsonb) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._spend_yukcoin_core(uuid, text, int, text, jsonb) TO service_role;
REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.random_match_join(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.random_match_join(text) TO authenticated, service_role;
