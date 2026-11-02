-- ══════════════════════════════════════════════════════════════════════
-- Poin hanya dipakai untuk: CALL, VIDEO CALL, MATCH (video), dan GIFT.
--
-- Keputusan user (2026-10-31):
--   • Filter gender, cari orang sekitar, undo pesan, edit pesan,
--     slot foto tambahan, mode hantu → TIDAK memotong poin.
--   • Match (random video call) → KENAKAN BIAYA seperti video call.
--
-- Implementasi:
--   1. call_billing_tick: hapus cabang "random = gratis" → match ditagih
--      dengan tarif call_video (unit_cost x menit), split 70/30 seperti biasa.
--   2. gate_feature: fitur non-call (gender_filter, nearby) → gratis
--      (return charged=0) supaya UI tidak pernah memotong poin.
--   3. spend_yukcoin: matikan debit untuk fitur non-call
--      (undo_message, edit_message, extra_photo_slot, ghost_mode).
-- ══════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════
-- 1. call_billing_tick — match (kind='random') ikut ditagih
-- ══════════════════════════════════════════════════════════════════════
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

  -- 2026-10-31: MATCH (kind='random') TIDAK lagi gratis — ditagih seperti
  -- video call. Match selalu video, jadi feat = call_video.
  feat := case when c.kind = 'random' then 'call_video'
               when c.call_type = 'audio' then 'call_audio'
               else 'call_video' end;

  select case when c.kind = 'random' then call_video_cost_per_min
              when c.call_type = 'audio' then call_audio_cost_per_min
              else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);

  -- Belum dijawab → belum ada tagihan.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;

  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);
  billable_minutes := (elapsed_sec + 59) / 60;

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
        'remaining', remaining, 'reason', 'insufficient');
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
        'remaining', remaining, 'reason', 'insufficient');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
    'remaining', remaining);
end;
$function$;

-- ══════════════════════════════════════════════════════════════════════
-- 2. gate_feature — fitur non-call jadi GRATIS (tidak memotong poin)
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.gate_feature(p_feature text, p_price_feature text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  cfg jsonb; unit_cost int;
  rkey text; already int; bal int; remaining int;
  today date;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  -- 2026-10-31: hanya call/video/gift yang memakai poin. Semua fitur
  -- akses-harian (filter gender, nearby, dll) GRATIS.
  return jsonb_build_object('ok', true, 'already', true, 'charged', 0,
    'remaining', public.yukcoin_total(me), 'free', true);

  -- (kode lama dipertahankan di bawah, tidak dieksekusi — untuk referensi)
  cfg := (select metered_pricing -> coalesce(p_price_feature, p_feature)
            from app_settings where id = 'global');
  if cfg is null then raise exception 'Unknown feature: %', p_feature; end if;
  unit_cost := coalesce((cfg->>'unit_cost')::int, 0);

  today := (now() at time zone 'Asia/Jakarta')::date;
  rkey := p_feature || ':' || today::text;

  select count(*) into already from public.yukcoin_consumptions
    where user_id = me and feature = p_feature and ref_id = rkey;
  if already > 0 then
    return jsonb_build_object('ok', true, 'already', true, 'charged', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  bal := public.yukcoin_total(me);
  if bal < unit_cost then raise exception 'YukCoin tidak cukup'; end if;

  remaining := public.ledger_spend(me, p_feature, unit_cost, rkey);
  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (me, p_feature, unit_cost, rkey,
            jsonb_build_object('date', today, 'daily', true));

  return jsonb_build_object('ok', true, 'already', false, 'charged', unit_cost,
    'remaining', remaining);
end;
$function$;

-- ══════════════════════════════════════════════════════════════════════
-- 3. spend_yukcoin — hanya untuk GIFT (fitur lain no-op / gratis)
-- ══════════════════════════════════════════════════════════════════════
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

  -- 2026-10-31: hanya GIFT yang boleh memotong poin lewat jalur ini.
  -- undo pesan, edit pesan, slot foto, mode hantu → GRATIS (no-op).
  if p_feature not in ('gift','gift_sent') then
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

REVOKE EXECUTE ON FUNCTION public.call_billing_tick(uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.gate_feature(text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.call_billing_tick(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.gate_feature(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.spend_yukcoin(uuid, text, int, text, jsonb) TO authenticated, service_role;
