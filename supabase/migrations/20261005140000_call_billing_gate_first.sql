-- ============================================================
-- call_billing_tick: gerbang fitur DI PALING ATAS (hemat).
--
-- SEBELUMNYA: fungsi membaca app_settings (unit_cost, call_cut_pct)
-- LEBIH DULU, baru mengecek feature_enabled_for('call_billing'). Saat fitur
-- billing OFF (mis. saat rollout/uji), tiap tick masih membayar 1-2 SELECT
-- config yang hasilnya dibuang. Pindahkan gate ke ATAS supaya jalur OFF
-- nyaris tanpa query. Tidak mengubah hasil saat fitur ON.
--
-- Perilaku & kontrak return TIDAK berubah (ok/can_continue/billed_minutes/
-- charged_total/per_minute/remaining/reason). Idempotent (create or replace).
-- ============================================================

create or replace function public.call_billing_tick(p_call_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c record;
  feat text; unit_cost int; cut_pct int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  afford int; charge_n int;
  remaining int;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  -- Gerbang fitur PALING ATAS — jalur OFF tak menyentuh config/billing.
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object(
      'ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  feat := case c.call_type when 'audio' then 'call_audio' else 'call_video' end;
  select case c.call_type
           when 'audio' then call_audio_cost_per_min
           else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);
  cut_pct := coalesce((select call_cut_pct from app_settings where id='global'), 70);

  -- Belum dijawab → belum ada tagihan.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;

  -- Detik berjalan SERVER-SIDE dari answered_at (anti-tamper client).
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);

  -- Menit berbayar = ceil(elapsed / 60). Menit pertama tetap ditagih penuh
  -- saat detik 1..60 (pembulatan ke atas) → tidak ada celah gratis.
  billable_minutes := (elapsed_sec + 59) / 60;

  -- Sudah ditagih berapa menit untuk call ini (idempoten).
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

    -- Tagih sebanyak yang sanggup (afford-guard → saldo tak pernah minus).
    afford := remaining / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public.charge_metered(me, feat, p_call_id::text, charge_n, c.callee_id);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select me, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g, 'call_type', c.call_type)
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
end; $$;
revoke execute on function public.call_billing_tick(uuid) from public, anon;
grant execute on function public.call_billing_tick(uuid) to authenticated, service_role;
