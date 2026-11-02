-- ============================================================
-- 20261102240000_call_free_limit_timezone.sql
-- BUGFIX: batas gratis panggilan female (30 menit/hari) memakai
-- `current_date` — zona waktu sesi DB (UTC), bukan zona waktu user.
--
-- Gejala: panggilan yang dijawab setelah tengah malam WIB tidak dihitung
-- ke kuota hari itu (karena `current_date` UTC masih kemarin) → female bisa
-- dapat lebih dari 30 menit gratis dalam satu hari kalender lokal.
-- Terbukti saat menulis test: 3 panggilan 10 menit yang dijawab 40 menit
-- lalu terbaca `v_free_used = 0` karena semuanya jatuh di "hari UTC"
-- sebelumnya.
--
-- Perbaikan: batas hari dihitung dalam Asia/Jakarta, konsisten dengan
-- perbaikan zona waktu di get_earnings_summary (20261101180000) dan
-- request_withdraw (20261102220000).
-- ============================================================

-- menyentuh: call_billing_tick
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
  feat text; unit_cost int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  remaining int; afford int; charge_n int;
  -- Awal hari ini dalam zona waktu USER (Asia/Jakarta) sebagai timestamptz.
  -- PENTING: bandingkan timestamptz dengan timestamptz. Membandingkan
  -- `answered_at >= (…::date)` SALAH — Postgres menafsirkan date sebagai
  -- UTC midnight, jadi panggilan yang dijawab 23:29 UTC (06:29 WIB hari
  -- berikutnya) tidak terhitung. Ini bug nyata yang terbukti di test.
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
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  -- ── Caller FEMALE = GRATIS (batas menit/hari) ──
  if v_caller_gender = 'female' then
    select coalesce(female_free_call_min_per_day, 30) into v_free_limit
      from app_settings where id = 'global';
    -- 2026-11-02: batas hari memakai Asia/Jakarta (bukan current_date UTC).
    select coalesce(sum(ceil(extract(epoch from
             (coalesce(cc.ended_at, now()) - cc.answered_at)) / 60)), 0)
      into v_free_used
      from public.calls cc
      join public.profiles pp on pp.id = cc.callee_id
     where cc.caller_id = me
       and cc.callee_id <> me
       and pp.gender = 'male'
       and cc.answered_at is not null
       and cc.answered_at >= v_day_start;
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
  -- Belum dijawab → belum ada tagihan.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);
  -- 2026-10-31: MATCH (kind='random') → menit ke-1 GRATIS.
  -- Call biasa: pembulatan ke atas (detik 1–60 sudah ditagih 1 menit).
  if c.kind = 'random' then
    billable_minutes := greatest(0, (elapsed_sec - 120)) / 60;
  else
    billable_minutes := (elapsed_sec + 59) / 60;
  end if;
  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = me and feature = feat and ref_id = p_call_id::text;
  to_bill := greatest(0, billable_minutes - already_billed);
  -- 2026-11-02: afford-check WAJIB memakai saldo PAID (topup+earned), bukan
  -- total. `charge_metered` menolak bucket `bonus`, jadi caller bonus-only
  -- yang lolos cek `yukcoin_total` akan membuat charge_metered melempar
  -- exception di tengah tick → panggilan error alih-alih berhenti halus.
  remaining := public.yukcoin_paid_total(me);
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

REVOKE EXECUTE ON FUNCTION public.call_billing_tick(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.call_billing_tick(uuid) TO authenticated, service_role;
