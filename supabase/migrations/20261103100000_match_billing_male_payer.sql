-- 20261103100000_match_billing_male_payer.sql
-- menyentuh: call_billing_tick, charge_metered
-- Random-match billing hybrid:
--   • payer SELALU pihak male, siapa pun caller-nya (perbaikan asimetri:
--     sebelumnya female-caller → call gratis total, female income 0).
--   • Gratis 30 detik pertama — siapa pun yang tutup <30s, male hanya
--     rugi pair fee 2 (anti-spam, tetap dipungut saat pair di match_join).
--   • Lolos 30 detik → biaya konek 10 (sekali, feature 'match_call',
--     split 70/30 → female +3), lalu call_video 20/menit (female +6).
--   • Tick boleh datang dari kedua pihak (caller maupun callee) — billing
--     tetap diarahkan ke payer lewat _charge_metered_core (tanpa auth
--     guard, pola _spend_yukcoin_core). Idempotent via yukcoin_consumptions
--     keyed by payer → tak bisa double-charge walau dua client tick.

-- ── 1. _charge_metered_core — badan charge_metered live (20261101190000)
-- minus syarat "payer harus participant pen-tick". SEMUA cabang live
-- dipertahankan: kill-switch points_enabled, guard recipient call,
-- harga call_audio/call_video dari kolom app_settings, wajib koin PAID
-- (yukcoin_paid_total + ledger_spend_paid — bonus gratis tetap tak bisa
-- membayar), income HANYA untuk recipient female, platform_revenue.
-- Satu-satunya penyesuaian: guard recipient mengenal kind='random' —
-- penerima income random = pihak FEMALE (bisa caller, bisa callee);
-- private tetap wajib callee seperti live.
CREATE OR REPLACE FUNCTION public._charge_metered_core(
  p_caller uuid, p_feature text, p_ref text,
  p_units integer DEFAULT 1, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cfg jsonb; unit_cost int; cut_pct int;
  total int; cut int; net int; remaining int; balance int;
  v_recipient_gender text;
  v_callee uuid;
  v_call_caller uuid;
  v_call_kind text;
begin
  -- Akses dijaga GRANT: EXECUTE dicabut dari authenticated — hanya
  -- dipanggil fungsi definer internal (call_billing_tick) & service_role.
  if p_caller is null then raise exception 'Not authenticated'; end if;
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  -- GUARD: untuk call, penerima income WAJIB pihak female call tersebut.
  -- Private → callee. Random → peserta mana pun (female bisa caller).
  -- Tanpa ini male bisa menyalurkan koin ke akun female miliknya sendiri.
  if p_feature in ('call_audio','call_video','match_call') then
    select c.callee_id, c.caller_id, c.kind into v_callee, v_call_caller, v_call_kind
      from public.calls c
     where c.id::text = p_ref;
    if v_callee is not null and p_recipient is not null then
      if v_call_kind = 'random' then
        if p_recipient <> v_callee and p_recipient <> v_call_caller then
          raise exception 'Forbidden: penerima bukan peserta call ini'
            using errcode = '42501';
        end if;
      elsif p_recipient <> v_callee then
        raise exception 'Forbidden: penerima bukan callee call ini'
          using errcode = '42501';
      end if;
    end if;
  end if;

  if p_feature = 'call_audio' then
    select call_audio_cost_per_min, call_cut_pct into unit_cost, cut_pct
      from app_settings where id = 'global';
  elsif p_feature = 'call_video' then
    select call_video_cost_per_min, call_cut_pct into unit_cost, cut_pct
      from app_settings where id = 'global';
  else
    select metered_pricing -> p_feature into cfg
      from app_settings where id = 'global';
    if cfg is null then
      raise exception 'Unknown metered feature: %', p_feature;
    end if;
    unit_cost := (cfg->>'unit_cost')::int;
    cut_pct   := (cfg->>'cut_pct')::int;
  end if;
  unit_cost := coalesce(unit_cost, 0);
  cut_pct   := coalesce(cut_pct, 0);

  total := unit_cost * p_units;
  if total <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  -- Call WAJIB pakai koin beli/penghasilan. Koin gratis (`bonus`) tidak
  -- boleh membayar menit call — 30% net-nya menjadi `earned` female
  -- (withdrawable) = koin gratis berubah jadi uang.
  balance := public.yukcoin_paid_total(p_caller);
  if balance < total then
    raise exception 'Koin beli/penghasilan tidak cukup (top-up dulu)'
      using errcode = '22023';
  end if;

  remaining := public.ledger_spend_paid(p_caller, p_feature, total, p_ref);

  cut := (total * cut_pct) / 100;
  net := total - cut;
  -- HANYA FEMALE yang dapat income.
  if p_recipient is not null and p_recipient <> p_caller and net > 0 then
    select gender into v_recipient_gender from public.profiles where id = p_recipient;
    if v_recipient_gender = 'female' then
      perform public.ledger_credit(p_recipient, 'earned', p_feature || '_income',
        net, p_ref, jsonb_build_object('from', p_caller, 'feature', p_feature,
        'gross', total, 'cut', cut));
      insert into public.point_events (user_id, event, amount, metadata)
        values (p_recipient, p_feature || '_income', net,
                jsonb_build_object('from', p_caller, 'ref', p_ref));
    end if;
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (p_feature, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, p_feature, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $function$;

-- ── 2. charge_metered → wrapper: guard client + delegasi ke core ──────
-- Tetap ada untuk kompatibilitas; EXECUTE tetap dicabut dari authenticated
-- (postur live 20261101100100) — tak ada pemanggil client langsung.
CREATE OR REPLACE FUNCTION public.charge_metered(
  p_caller uuid, p_feature text, p_ref text,
  p_units integer DEFAULT 1, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- GUARD KEAMANAN: user hanya boleh menagih DIRINYA sendiri.
  -- call_billing_tick memakai _charge_metered_core untuk cross-payer.
  if auth.uid() is not null and p_caller is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh menagih user lain'
      using errcode = '42501';
  end if;
  return public._charge_metered_core(p_caller, p_feature, p_ref, p_units, p_recipient);
end; $function$;

-- ── 3. call_billing_tick — payer=male untuk random ────────────────────
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
  v_connect_cost int := 0;
  v_connect_billed boolean := false;
  v_free_seconds_left int := 0;
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
  -- Random: kedua peserta boleh tick (billing diarahkan ke payer).
  -- Private: tetap hanya caller yang men-tick (perilaku lama).
  if c.kind is distinct from 'random' and c.caller_id <> me then
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
      v_payer := c.caller_id; -- fallback gender tak dikenal
    end if;
    v_recipient := case when v_payer = c.caller_id then c.callee_id
                        else c.caller_id end;
  else
    v_payer := c.caller_id;
    v_recipient := c.callee_id;
  end if;

  -- ── Caller FEMALE = GRATIS (batas menit/hari) — private saja ──
  -- Random TIDAK gratis walau caller female: payer-nya tetap male.
  if c.kind is distinct from 'random' and v_caller_gender = 'female' then
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

  -- MATCH (kind='random') → gratis 30 DETIK pertama. Menit N berbayar
  -- menutup jendela [30+(N-1)*60, 30+N*60) — tagih di awal jendelanya
  -- (detik 30, 90, 150, …) supaya tak ada menit gratis terselip di ujung.
  -- Call biasa: pembulatan ke atas (detik 1–60 sudah ditagih 1 menit).
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
  -- 2026-11-02: afford-check WAJIB memakai saldo PAID (topup+earned), bukan
  -- total. `charge_metered` menolak bucket `bonus`, jadi caller bonus-only
  -- yang lolos cek `yukcoin_total` akan membuat charge_metered melempar
  -- exception di tengah tick → panggilan error alih-alih berhenti halus.
  v_paid := public.yukcoin_paid_total(v_payer);
  remaining := public.yukcoin_total(me);

  -- ── Biaya KONEK (sekali per match, saat lolos 30 detik gratis) ──
  -- Female +30% dari harga konek (cut_pct dari metered_pricing.match_call).
  -- Ditagih SEBELUM menit — tak lolos grace → tak ada fee yang hangus.
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
        charge_n, v_recipient);
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
    'free_seconds_left', v_free_seconds_left);
end; $function$;

-- ── 4. metered_pricing += match_call (biaya konek 10, split 70/30) ────
UPDATE public.app_settings
   set metered_pricing = coalesce(metered_pricing, '{}'::jsonb)
       || '{"match_call":{"model":"per_match","unit_cost":10,"cut_pct":70}}'::jsonb
 where id = 'global';

-- ── Grants ───────────────────────────────────────────────────────────
-- SAFE: _charge_metered_core & charge_metered dicabut dari authenticated —
-- sama dengan postur live (20261101100100 §4): billing call tetap jalan via
-- call_billing_tick SECURITY DEFINER; TIDAK ada pemanggil client langsung.
REVOKE EXECUTE ON FUNCTION public._charge_metered_core(uuid, text, text, int, uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._charge_metered_core(uuid, text, text, int, uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.charge_metered(uuid, text, text, int, uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.call_billing_tick(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.call_billing_tick(uuid) TO authenticated, service_role;
