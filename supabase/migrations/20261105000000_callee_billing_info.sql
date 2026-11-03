-- call_billing_tick: cabang info-only untuk sisi PENERIMA (non-payer).
-- Tujuan: layar call sisi penerima (umumnya female) bisa menampilkan
-- pendapatan live (+N YukCoin) tanpa ikut menagih. Callee private call
-- sebelumnya ditolak 'Only caller can be billed' → tak pernah dapat data.
-- Tak ada debit/insert di cabang ini — murni baca ledger income milik
-- pemanggil untuk call tsb. Payer tetap menempuh jalur billing normal.

CREATE OR REPLACE FUNCTION public.call_billing_tick(p_call_id uuid)
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
  v_day_start timestamptz :=
    (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
       AT TIME ZONE 'Asia/Jakarta');
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;
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
  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  -- Gender CALLER yang sebenarnya (bukan pemanggil tick): tick kini boleh
  -- dari kedua peserta — pakai `me` di sini dulu membuat callee-tick random
  -- salah resolve payer dan private callee-tick kena cabang free-female.
  select gender into v_caller_gender from public.profiles where id = c.caller_id;
  -- Private: kedua peserta boleh tick — caller menagih, callee baca info.
  -- Pihak ketiga tetap ditolak.
  if c.kind is distinct from 'random' and c.caller_id <> me
     and c.callee_id <> me then
    raise exception 'Only caller can be billed';
  end if;
  if c.kind = 'random' and me <> c.caller_id and me <> c.callee_id then
    raise exception 'Only participants';
  end if;

  -- ── Payer & recipient ──
  -- Random: pihak MALE membayar, pihak FEMALE menerima split (kebalikan
  -- dari asumsi caller=payer lama — caller match = siapa yang join kedua,
  -- murni kebetulan sisi signaling, bukan ekonomi). Private: caller bayar.
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
  -- Pendapatan live pemanggil tick (0 untuk payer — dia tidak menerima
  -- income). Sumber kebenaran = ledger yang ditulis _charge_metered_core.
  select coalesce(sum(amount),0) into v_income
    from public.coin_ledger
   where user_id = me and ref_id = p_call_id::text
     and type like '%\_income' escape '\';

  -- ── Caller FEMALE = GRATIS (batas menit/hari) — private saja ──
  -- Random TIDAK gratis walau caller female: payer-nya tetap male.
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
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me),
      'income_total', v_income,
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
  v_anchor := case when c.kind = 'random'
                   then coalesce(c.media_connected_at, c.answered_at)
                   else c.answered_at end;
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - v_anchor)))::int);

  if c.kind = 'random' then
    billable_minutes := case when elapsed_sec >= 30
                        then 1 + (elapsed_sec - 30) / 60 else 0 end;
    v_free_seconds_left := greatest(0, 30 - elapsed_sec);
  else
    billable_minutes := (elapsed_sec + 59) / 60;
  end if;

  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = v_payer and feature = feat and ref_id = p_call_id::text;
  to_bill := greatest(0, billable_minutes - already_billed);
  v_paid := public.yukcoin_paid_total(v_payer);
  remaining := public.yukcoin_total(me);

  if c.kind = 'random' and elapsed_sec >= 30 then
    select coalesce((metered_pricing->'match_call'->>'unit_cost')::int, 10)
      into v_connect_cost from app_settings where id = 'global';
    select exists (
      select 1 from public.yukcoin_consumptions
       where user_id = v_payer and feature = 'match_call'
         and ref_id = p_call_id::text
    ) into v_connect_billed;
    if not v_connect_billed then
      if v_paid < v_connect_cost then
        return jsonb_build_object('ok', true, 'can_continue', false,
          'billed_minutes', already_billed,
          'charged_total', already_billed * unit_cost,
          'per_minute', unit_cost,
          'remaining', remaining, 'reason', 'insufficient',
          'free_seconds_left', 0);
      end if;
      perform public._charge_metered_core(v_payer, 'match_call',
        p_call_id::text, 1, v_recipient);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        values (v_payer, 'match_call', v_connect_cost, p_call_id::text,
                jsonb_build_object('kind', 'random', 'connect', true));
      v_connect_billed := true;
      v_paid := public.yukcoin_paid_total(v_payer);
      remaining := public.yukcoin_total(me);
    end if;
  end if;

  if to_bill > 0 then
    if v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost
          + (case when v_connect_billed then v_connect_cost else 0 end),
        'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
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
        from generate_series(1, charge_n) g;
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
        'free_seconds_left', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost
      + (case when v_connect_billed then v_connect_cost else 0 end),
    'per_minute', unit_cost,
    'remaining', remaining,
    'income_total', v_income,
    'free_seconds_left', v_free_seconds_left);
end;
$function$;
