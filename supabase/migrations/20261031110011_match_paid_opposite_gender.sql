-- ══════════════════════════════════════════════════════════════════════
-- Match (Random Video Call) berbayar + lawan jenis otomatis
--
-- Keputusan user (2026-10-31):
--   • Klik Match / Next = −2 poin (biaya pencarian, HANGUS bila gagal/batal).
--   • Match menit ke-1 GRATIS, menit ke-2+ = tarif video (20/menit).
--   • Female TIDAK dikenakan biaya (tidak pernah keluar koin).
--   • Lawan jenis otomatis: male↔female. Tidak ada pilihan "Semua".
--   • Radar & hitungan online hanya lawan jenis.
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. spend_yukcoin: izinkan `match_search` ──
CREATE OR REPLACE FUNCTION public.spend_yukcoin(p_user uuid, p_feature text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e int; b int; need int; take int; tier text;
begin
  if auth.uid() is not null and p_user is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh mendebit saldo user lain'
      using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  -- 2026-10-31: hanya GIFT + biaya pencarian MATCH yang memotong poin.
  -- undo, edit, slot foto, mode hantu, filter, nearby → GRATIS.
  if p_feature not in ('gift','gift_sent','match_search') then
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

  return jsonb_build_object('tier', tier, 'charged', p_amount,
    'remaining', public.yukcoin_total(p_user));
end;
$function$;

-- ── 2. random_match_join: paksa lawan jenis ──
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
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;

  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false)
    into v_all, v_anon from public.app_settings where id = 'global';
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

  select rq.* into q
    from public.random_match_queue rq
   where rq.user_id <> me
     and rq.matched_call_id is null
     and rq.pinged_at > now() - interval '30 seconds'
     and (v_want = 'all' or rq.gender = v_want)
     and (rq.want_gender = 'all' or rq.want_gender = v_gender)
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

-- ── 3. random_match_stats: radar & hitungan hanya lawan jenis ──
CREATE OR REPLACE FUNCTION public.random_match_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  my_gender text;
  v_opposite text;
  v_waiting int;
  v_online int;
  v_sample jsonb;
  v_excl uuid[];
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select lat, lon, gender into my_lat, my_lon, my_gender
    from public.profiles where id = me;

  -- Lawan jenis: male↔female. Selain itu (other/null) = semua.
  v_opposite := case my_gender
                  when 'male' then 'female'
                  when 'female' then 'male'
                  else null
                end;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  select count(*) into v_waiting
    from public.random_match_queue q
    join public.profiles p on p.id = q.user_id
   where q.matched_call_id is null
     and q.pinged_at > now() - interval '30 seconds'
     and (v_opposite is null or p.gender = v_opposite);

  select count(*) into v_online
    from public.profiles p
   where p.id <> me
     and p.status in ('online', 'idle')
     and p.last_seen >= now() - interval '30 minutes'
     and (v_opposite is null or p.gender = v_opposite)
     and not (p.id = any (v_excl))
     and not exists (select 1 from public.ghost_mode_active g
                      where g.user_id = p.id and g.expires_at > now());

  select coalesce(jsonb_agg(x order by x->>'distance_km' nulls last), '[]'::jsonb)
    into v_sample
    from (
      select jsonb_build_object(
               'uid', p.id,
               'nickname', p.nickname,
               'gender', p.gender,
               'avatar', case when public.privacy_can_view(p.id, 'profile_photo', me)
                              then p.avatar else '' end,
               'city', p.city,
               'distance_km', case when my_lat is not null and p.lat is not null and p.lon is not null
                                   then round((earth_distance(ll_to_earth(my_lat, my_lon),
                                                              ll_to_earth(p.lat, p.lon)) / 1000.0)::numeric, 1)
                                   else null end
             ) as x
        from public.profiles p
       where p.id <> me
         and p.status in ('online', 'idle')
         and p.last_seen >= now() - interval '30 minutes'
         and (v_opposite is null or p.gender = v_opposite)
         and public.privacy_can_view(p.id, 'presence', me)
         and not (p.id = any (v_excl))
         and not exists (select 1 from public.ghost_mode_active g
                          where g.user_id = p.id and g.expires_at > now())
         and not exists (select 1 from public.blocks b
                          where (b.blocker_id = me and b.blocked_id = p.id)
                             or (b.blocker_id = p.id and b.blocked_id = me))
       order by p.last_seen desc
       limit 8
    ) s;

  return jsonb_build_object('waiting', v_waiting, 'online', v_online,
    'sample', v_sample, 'opposite_gender', v_opposite);
end;
$function$;

-- ── 4. call_billing_tick: match menit ke-1 GRATIS ──
CREATE OR REPLACE FUNCTION public.call_billing_tick(p_call_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  c record;
  feat text; unit_cost int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  afford int; charge_n int;
  remaining int;
  points_on boolean;
  v_caller_gender text;
  v_free_limit int;
  v_free_used numeric;
  v_free_seconds_left int := 0;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    return jsonb_build_object(
      'ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  -- ── Caller FEMALE = GRATIS (batas menit/hari) ──
  select gender into v_caller_gender from public.profiles where id = me;
  if v_caller_gender = 'female' then
    select coalesce(female_free_call_min_per_day, 30) into v_free_limit
      from app_settings where id = 'global';
    select coalesce(sum(ceil(extract(epoch from
             (coalesce(cc.ended_at, now()) - cc.answered_at)) / 60)), 0)
      into v_free_used
      from public.calls cc
      join public.profiles pp on pp.id = cc.callee_id
     where cc.caller_id = me
       and cc.callee_id <> me
       and pp.gender = 'male'
       and cc.answered_at is not null
       and cc.answered_at >= current_date;
    if v_free_used >= v_free_limit then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
        'remaining', public.yukcoin_total(me),
        'reason', 'free_limit',
        'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
    end if;
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me),
      'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
  end if;

  feat := case when c.kind = 'random' then 'call_video'
               when c.call_type = 'audio' then 'call_audio'
               else 'call_video' end;

  select case when c.kind = 'random' then call_video_cost_per_min
              when c.call_type = 'audio' then call_audio_cost_per_min
              else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);

  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;

  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);

  -- 2026-10-31: MATCH (kind='random') → menit ke-1 GRATIS.
  -- Call biasa: pembulatan ke atas (detik 1–60 sudah ditagih 1 menit).
  if c.kind = 'random' then
    billable_minutes := greatest(0, elapsed_sec / 60 - 1);  -- 0–119 s = 0
    v_free_seconds_left := greatest(0, 120 - elapsed_sec);
  else
    billable_minutes := (elapsed_sec + 59) / 60;
  end if;

  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = me and feature = feat and ref_id = p_call_id::text;

  to_bill := greatest(0, billable_minutes - already_billed);
  remaining := public.yukcoin_total(me);

  if to_bill > 0 then
    if remaining < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
    end if;
    afford := remaining / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public.charge_metered(me, feat, p_call_id::text, charge_n, c.callee_id);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select me, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g,
                                  'call_type', c.call_type,
                                  'kind', coalesce(c.kind, 'private'))
        from generate_series(1, charge_n) g;
      already_billed := already_billed + charge_n;
      remaining := public.yukcoin_total(me);
    end if;
    if charge_n < to_bill or remaining < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
    'remaining', remaining, 'free_seconds_left', v_free_seconds_left);
end;
$function$;

REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.random_match_join(text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.random_match_stats() FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.call_billing_tick(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.random_match_join(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.random_match_stats() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.call_billing_tick(uuid) TO authenticated, service_role;
