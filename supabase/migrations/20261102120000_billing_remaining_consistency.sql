-- ============================================================
-- 120000 — call_billing_tick: `remaining` konsisten = yukcoin_total
--          + match tertagih mulai detik ke-120 (bukan 180)
-- ============================================================
-- menyentuh: call_billing_tick
--
-- Masalah 1 — counter koin di layar call "loncat" (986 ↔ 1021):
-- `remaining` yang dikirim ke client memakai DUA definisi:
--   • pra-charge  → yukcoin_paid_total (topup+earned = 986)
--   • pasca-charge & semua early-return → yukcoin_total (semua
--     bucket = 1021)
-- Client menaruh `remaining` langsung ke saldo UI, lalu poll
-- profiles.points mengoreksi → angka tampak berubah-ubah.
-- Fix: `remaining` SELALU yukcoin_total (definisi saldo UI).
-- `v_paid` tetap untuk afford-check (charge_metered menolak bonus).
--
-- Masalah 2 — match tidak pernah tertagih:
-- Migrasi 240000 (fix timezone) menulis `(elapsed_sec - 120) / 60`
-- → menit tertagih pertama baru muncul di elapsed 180 dtk ≈ 3 menit.
-- Desain "menit ke-1 GRATIS" = tagih mulai 120 dtk → kembalikan
-- `elapsed_sec / 60 - 1` seperti 110011/190000.
-- ============================================================

create or replace function public.call_billing_tick(p_call_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public
as $function$
declare
  me uuid := auth.uid();
  c record;
  v_all boolean; v_anon boolean; points_on boolean;
  v_free_limit int; v_free_used int;
  v_caller_gender text;
  feat text; unit_cost int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  remaining int; v_paid int; afford int; charge_n int;
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
  -- MATCH (kind='random') → menit ke-1 GRATIS: tagihan mulai detik 120
  -- (menit ke-2+ berbayar). Call biasa: pembulatan ke atas.
  if c.kind = 'random' then
    billable_minutes := greatest(0, elapsed_sec / 60 - 1);  -- 0–119 s = 0
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
  v_paid := public.yukcoin_paid_total(me);
  remaining := public.yukcoin_total(me);
  if to_bill > 0 then
    if v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient');
    end if;
    afford := v_paid / greatest(unit_cost, 1);
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
      v_paid := public.yukcoin_paid_total(me);
      remaining := public.yukcoin_total(me);
    end if;
    if charge_n < to_bill or v_paid < unit_cost then
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

revoke execute on function public.call_billing_tick(uuid) from public, anon;
grant execute on function public.call_billing_tick(uuid) to authenticated, service_role;
