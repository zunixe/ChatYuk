-- ══════════════════════════════════════════════════════════════════════
-- Billing call (2026-11-09):
-- 1. FEATURE_DISABLED hanya untuk call random (private call tak lagi gratis
--    saat flag random_call mati).
-- 2. Call random baru ditagih setelah media_connected_at (tanpa fallback
--    answered_at) — tak ada biaya konek bila video tak pernah tersambung.
-- 3. metered_pricing_public + biaya match (cari/konek/gratis detik) supaya
--    UI tidak lagi hardcode.
-- ══════════════════════════════════════════════════════════════════════

-- menyentuh: call_billing_tick
create or replace function public.call_billing_tick(p_call_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  c record;
  v_all boolean; v_anon boolean; points_on boolean;
  v_free_limit int; v_free_used int;
  v_caller_gender text;
  v_callee_gender text;
  feat text; unit_cost int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  remaining int; v_paid int; afford int; charge_n int;
  v_payer uuid; v_recipient uuid;
  v_income int;
  v_connect_cost int := 0;
  v_connect_billed boolean := false;
  v_free_seconds_left int := 0;
  v_anchor timestamptz;
  v_end timestamptz;
  v_ended boolean;
  v_day_start timestamptz :=
    (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
       AT TIME ZONE 'Asia/Jakarta');
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false),
         coalesce(points_enabled, true)
    into v_all, v_anon, points_on
    from app_settings where id = 'global';
  if not v_all then raise exception 'CALL_DISABLED'; end if;
  select gender into v_caller_gender from public.profiles where id = me;
  if not v_anon and not exists (
    select 1 from public.profiles p where p.id = me and p.is_registered) then
    raise exception 'CALL_REGISTERED_ONLY';
  end if;
  if points_on is false then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  -- A2a: KUNCI baris call — dua tick bersamaan (payer+callee / dua device)
  -- terserial → tidak ada double-charge.
  select * into c from public.calls where id = p_call_id for update;
  if not found then raise exception 'Call not found'; end if;
  -- 2026-11-09: flag random_call hanya untuk call RANDOM. Dulu dicek untuk
  -- semua call → saat flag mati, tick private call melempar FEATURE_DISABLED
  -- dan klien menelannya = private call GRATIS tanpa ketahuan.
  if c.kind = 'random' and not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;

  select gender into v_caller_gender from public.profiles where id = c.caller_id;
  if c.kind is distinct from 'random' and c.caller_id <> me
     and c.callee_id <> me then
    raise exception 'Only caller can be billed';
  end if;
  if c.kind = 'random' and me <> c.caller_id and me <> c.callee_id then
    raise exception 'Only participants';
  end if;

  -- ── Payer & recipient ──
  if c.kind = 'random' then
    select gender into v_callee_gender from public.profiles where id = c.callee_id;
    if v_caller_gender = 'male' then
      v_payer := c.caller_id;
    elsif v_callee_gender = 'male' then
      v_payer := c.callee_id;
    else
      v_payer := c.caller_id;
    end if;
    v_recipient := case when v_payer = c.caller_id then c.callee_id
                        else c.caller_id end;
  else
    v_payer := c.caller_id;
    v_recipient := c.callee_id;
  end if;

  if me <> v_payer and me <> v_recipient then
    raise exception 'Only participants';
  end if;

  select coalesce(sum(amount),0) into v_income
    from public.coin_ledger
   where user_id = me and ref_id = p_call_id::text
     and type like '%\_income' escape '\';

  -- A2b: call sudah berakhir → elapsed di-cap ke ended_at. Tick setelah
  -- ended hanya menagih menit yang BENAR-BENAR terpakai, lalu melaporkan
  -- can_continue=false agar client berhenti (tidak ada tagihan baru).
  v_ended := c.ended_at is not null
             or c.status in ('ended','canceled','declined','missed','busy');
  -- N1 (2026-11-09): ended_at TIDAK boleh di masa depan (dulu peserta bisa
  -- set ended_at=besok → tick menagih semua menit sampai saldo habis).
  v_end   := least(coalesce(c.ended_at, now()), now());

  feat := case when c.kind = 'random' then 'call_video'
               when c.call_type = 'audio' then 'call_audio'
               else 'call_video' end;
  select case when c.kind = 'random' then call_video_cost_per_min
              when c.call_type = 'audio' then call_audio_cost_per_min
              else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);

  if c.kind = 'random' then
    select coalesce((metered_pricing->'match_call'->>'unit_cost')::int, 10)
      into v_connect_cost from app_settings where id = 'global';
  end if;

  if c.answered_at is not null then
    -- 2026-11-09: random ditagih HANYA setelah video benar-benar tersambung
    -- (media_connected_at, distempel salah satu sisi via touch_call). Dulu
    -- fallback ke answered_at → male kena biaya konek walau video tak
    -- pernah tampil.
    v_anchor := case when c.kind = 'random'
                     then c.media_connected_at
                     else c.answered_at end;
    elapsed_sec := case when v_anchor is null then 0 else
      greatest(0, floor(extract(epoch from (v_end - v_anchor)))::int) end;
  else
    elapsed_sec := 0;
  end if;

  if c.kind = 'random' then
    billable_minutes := case when elapsed_sec >= 30
                        then 1 + (elapsed_sec - 30) / 60 else 0 end;
    v_free_seconds_left := case when v_ended then 0
                            else greatest(0, 30 - elapsed_sec) end;
  else
    billable_minutes := (elapsed_sec + 59) / 60;
  end if;

  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = v_payer and feature = feat and ref_id = p_call_id::text;
  v_connect_billed := exists (
    select 1 from public.yukcoin_consumptions
     where user_id = v_payer and feature = 'match_call'
       and ref_id = p_call_id::text
  );

  -- ── A2c: RECIPIENT READ-ONLY ──
  -- Tick penerima tidak lagi menagih: ia hanya membaca kondisi billing
  -- (income_total, billed_minutes, charged_total) untuk ditampilkan.
  -- Ini menutup jalur "female terus tick call lama → koin male terkuras".
  -- Charge tetap mungkin hanya dari sisi payer; kunci baris + unique index
  -- menjamin idempoten walau kedua sisi tick bersamaan.
  if me = v_recipient and me <> v_payer then
    return jsonb_build_object('ok', true,
      'can_continue', not v_ended,
      'billed_minutes', already_billed,
      'charged_total', already_billed * unit_cost
        + (case when v_connect_billed then v_connect_cost else 0 end),
      'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me),
      'income_total', v_income,
      'free_seconds_left', v_free_seconds_left,
      'ended', v_ended,
      'role', 'recipient');
  end if;

  -- ── Caller FEMALE = GRATIS (batas menit/hari) — private saja ──
  if c.kind is distinct from 'random' and v_caller_gender = 'female' then
    select coalesce(female_free_call_min_per_day, 30) into v_free_limit
      from app_settings where id = 'global';
    select coalesce(sum(ceil(extract(epoch from
             (coalesce(cc.ended_at, now()) - cc.answered_at)) / 60)), 0)
      into v_free_used
      from public.calls cc
      join public.profiles pp on pp.id = cc.callee_id
     where cc.caller_id = c.caller_id
       and cc.callee_id <> me
       and pp.gender = 'male'
       and cc.answered_at is not null
       and cc.answered_at >= v_day_start;
    if v_free_used >= v_free_limit then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
        'remaining', public.yukcoin_total(me),
        'reason', 'free_limit',
        'income_total', v_income,
        'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
    end if;
    return jsonb_build_object('ok', true,
      'can_continue', not v_ended,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me),
      'income_total', v_income,
      'ended', v_ended,
      'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
  end if;

  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', not v_ended,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me), 'ended', v_ended);
  end if;

  to_bill := greatest(0, billable_minutes - already_billed);
  v_paid := public.yukcoin_paid_total(v_payer);
  remaining := public.yukcoin_total(me);

  -- Connect fee (random, lolos 30 dtk)
  if c.kind = 'random' and elapsed_sec >= 30 and not v_connect_billed then
    if v_paid < v_connect_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost,
        'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0, 'ended', v_ended);
    end if;
    perform public._charge_metered_core(v_payer, 'match_call',
      p_call_id::text, 1, v_recipient);
    insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
      values (v_payer, 'match_call', v_connect_cost, p_call_id::text,
              jsonb_build_object('kind', 'random', 'connect', true,
                                 'minute', 0))
      on conflict do nothing;
    v_connect_billed := true;
    v_paid := public.yukcoin_paid_total(v_payer);
    remaining := public.yukcoin_total(me);
  end if;

  if to_bill > 0 then
    if v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost
          + (case when v_connect_billed then v_connect_cost else 0 end),
        'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0, 'ended', v_ended);
    end if;
    afford := v_paid / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public._charge_metered_core(v_payer, feat, p_call_id::text,
        charge_n, v_recipient,
        case when c.kind = 'random' then 'match_call' else null end);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select v_payer, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g,
                                  'call_type', c.call_type,
                                  'kind', coalesce(c.kind, 'private'))
        from generate_series(1, charge_n) g
        on conflict do nothing;
      already_billed := already_billed + charge_n;
      v_paid := public.yukcoin_paid_total(v_payer);
      remaining := public.yukcoin_total(me);
    end if;
    if charge_n < to_bill or v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost
          + (case when v_connect_billed then v_connect_cost else 0 end),
        'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0, 'ended', v_ended);
    end if;
  end if;

  return jsonb_build_object('ok', true,
    'can_continue', not v_ended,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost
      + (case when v_connect_billed then v_connect_cost else 0 end),
    'per_minute', unit_cost,
    'remaining', remaining,
    'income_total', v_income,
    'free_seconds_left', v_free_seconds_left,
    'ended', v_ended);
end;
$function$;

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
    'match_free_seconds', 30
  ) from app_settings where id = 'global');
end; $function$;
