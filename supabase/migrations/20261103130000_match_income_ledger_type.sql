-- 2026-11-03: income per-menit MATCH harus `match_call_income`, bukan
-- `call_video_income`.
--
-- Model billing match (konek 10 + per-menit tarif video) menagih lewat
-- `_charge_metered_core(p_feature='call_video')` → female menerima
-- `call_video_income` → rincian Saldo menampilkannya di "Panggilan
-- Privasi" (padahal sumbernya match). Fee konek sudah benar
-- ('match_call'/'match_call_income'); per-menit tertinggal.
--
-- `coin_ledger` APPEND-ONLY (trigger menolak UPDATE/DELETE) → tipe harus
-- benar sejak INSERT; baris lama tak bisa di-retype.
--
-- Fix 3 lapis:
-- 1. `_charge_metered_core` + param opsional `p_ledger_type`: pemakaian
--    fitur (pricing/cut) tetap dari p_feature, tapi TIPE ledger/spend/
--    income/revenue ditulis p_ledger_type → match per-menit tertulis
--    'match_call' + 'match_call_income'.
-- 2. `call_billing_tick`: charge per-menit untuk kind='random' memakai
--    p_ledger_type='match_call'.
-- 3. `get_earnings_summary`: bucket match_call dihitung via JOIN calls —
--    'match_call_income' ATAU income call_* yang ref_id-nya call
--    kind='random' → baris lama ('call_video_income' hasil match) ikut
--    pindah kategori tanpa perlu update ledger (yang memang mustahil).

-- Signature berubah (param ke-6 opsional) → drop versi lama dulu supaya
-- panggilan 5-arg tidak ambigu di antara dua overload.
drop function if exists public._charge_metered_core(uuid, text, text, integer, uuid);

create or replace function public._charge_metered_core(p_caller uuid,
  p_feature text, p_ref text, p_units integer default 1,
  p_recipient uuid default null::uuid,
  p_ledger_type text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  cfg jsonb; unit_cost int; cut_pct int;
  total int; cut int; net int; remaining int; balance int;
  v_recipient_gender text;
  v_callee uuid;
  v_call_caller uuid;
  v_call_kind text;
  -- Tipe ledger yang ditulis (spend/income/revenue). Default = p_feature
  -- (perilaku lama); match per-menit memakai 'match_call' supaya income
  -- female masuk 'match_call_income', bukan 'call_video_income'.
  v_ltype text := coalesce(nullif(p_ledger_type, ''), p_feature);
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

  remaining := public.ledger_spend_paid(p_caller, v_ltype, total, p_ref);

  cut := (total * cut_pct) / 100;
  net := total - cut;
  -- HANYA FEMALE yang dapat income.
  if p_recipient is not null and p_recipient <> p_caller and net > 0 then
    select gender into v_recipient_gender from public.profiles where id = p_recipient;
    if v_recipient_gender = 'female' then
      perform public.ledger_credit(p_recipient, 'earned', v_ltype || '_income',
        net, p_ref, jsonb_build_object('from', p_caller, 'feature', p_feature,
        'gross', total, 'cut', cut));
      insert into public.point_events (user_id, event, amount, metadata)
        values (p_recipient, v_ltype || '_income', net,
                jsonb_build_object('from', p_caller, 'ref', p_ref));
    end if;
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (v_ltype, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, v_ltype, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $function$;

create or replace function public.call_billing_tick(p_call_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path TO 'public'
as $function$
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
        charge_n, v_recipient,
        -- Match per-menit → tipe 'match_call' ('_income' untuk female)
        -- supaya rincian Saldo/riwayat masuk "Panggilan Match".
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
    'free_seconds_left', v_free_seconds_left);
end; $function$;

-- Bucket match_call memakai JOIN ke calls (kind='random') — mencakup
-- income lama yang tertulis 'call_video_income' sebelum fix ini (ledger
-- append-only, tak bisa di-retype) DAN income baru 'match_call_income'.
create or replace function public.get_earnings_summary(p_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path TO 'public'
as $function$
DECLARE
    result jsonb;
    v_total bigint;
    v_weekly bigint;
    v_today bigint;
    v_gift bigint;
    v_mission bigint;
    v_private_call bigint;
    v_match_call bigint;
    v_other bigint;
    v_withdrawable bigint;
    v_total_balance bigint;
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
    v_day_start timestamptz;
    v_week_start timestamptz;
BEGIN
    if coalesce(auth.role(), '') <> 'service_role'
       and auth.uid() is not null
       and p_user_id is distinct from auth.uid() then
        raise exception 'Forbidden: tidak boleh membaca saldo user lain'
            using errcode = '42501';
    end if;

    -- Awal hari/minggu dalam Asia/Jakarta, sebagai timestamptz. Bandingkan
    -- timestamptz dengan timestamptz — `date_trunc('day', now() at time zone
    -- …)` mengembalikan timestamp tanpa zona yang lalu dibandingkan dengan
    -- kolom timestamptz → salah tafsir (terbukti: baris 23:29 UTC di hari
    -- berikutnya WIB tidak terhitung).
    v_day_start  := (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
                       AT TIME ZONE 'Asia/Jakarta');
    v_week_start := ((date_trunc('week',
                       (now() AT TIME ZONE 'Asia/Jakarta'))::timestamp)
                       AT TIME ZONE 'Asia/Jakarta');

    SELECT
        COALESCE(SUM(l.amount), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.created_at >= v_week_start), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.created_at >= v_day_start), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.type IN ('gift_recv','coin_received')), 0),
        COALESCE(SUM(l.amount) FILTER (WHERE l.type = 'mission_reward'), 0),
        -- Privasi = income call_* yang ref_id-nya BUKAN call random.
        COALESCE(SUM(l.amount) FILTER (
            WHERE l.type IN ('call_audio_income','call_video_income',
                             'private_call_income')
              AND rc.id is null), 0),
        -- Match = tipe match_call_income ATAU income call_* dari call random.
        COALESCE(SUM(l.amount) FILTER (
            WHERE l.type = 'match_call_income'
               OR (l.type IN ('call_audio_income','call_video_income')
                   AND rc.id is not null)), 0),
        COALESCE(SUM(l.amount) FILTER (
            WHERE l.type NOT IN ('gift_recv','coin_received','mission_reward',
                                 'call_audio_income','call_video_income',
                                 'private_call_income','match_call_income')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission,
         v_private_call, v_match_call, v_other
    FROM public.coin_ledger l
    LEFT JOIN public.calls rc
      ON rc.id::text = l.ref_id AND rc.kind = 'random'
    WHERE l.user_id = p_user_id
      AND l.amount > 0
      AND l.type IN (
            'gift_recv','coin_received',
            'mission_reward',
            'call_audio_income','call_video_income',
            'private_call_income','match_call_income',
            'photo_income','photo_unlock_income',
            'subscribe_income'
      )
      AND coalesce(l.ref_id, '') NOT IN ('t','test-income')
      AND coalesce(l.ref_id, '') NOT LIKE 'cleanup\_%'
      AND coalesce(l.ref_id, '') NOT LIKE 'female_bonus_reset\_%';

    -- 2026-11-02: yang bisa DITARIK = bucket `earned` saja (sama dengan
    -- validasi request_withdraw). `total_balance` = semua bucket, untuk
    -- informasi — jangan tertukar.
    SELECT COALESCE(SUM(amount) FILTER (WHERE bucket = 'earned'), 0)
      INTO v_withdrawable
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

    SELECT COALESCE(SUM(amount), 0) INTO v_total_balance
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

    SELECT
        COUNT(*) FILTER (WHERE call_type = 'video'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE call_type = 'video' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint,
        COUNT(*) FILTER (WHERE kind = 'random'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE kind = 'random' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint
    INTO v_video_calls, v_video_seconds, v_match_calls, v_match_seconds
    FROM public.calls
    WHERE (caller_id = p_user_id OR callee_id = p_user_id)
      AND status = 'ended';
    SELECT COUNT(*), COUNT(*) FILTER (WHERE answered_at IS NOT NULL)
    INTO v_private_total, v_private_answered
    FROM public.calls
    WHERE callee_id = p_user_id
      AND coalesce(kind, '') <> 'random'
      AND status = 'ended';
    result := jsonb_build_object(
        'total_earnings', v_total,
        'weekly_earnings', v_weekly,
        'today_earnings', v_today,
        'withdrawable', v_withdrawable,
        'total_balance', v_total_balance,
        'breakdown', jsonb_build_object(
            'private_call', v_private_call,
            'match_call', v_match_call,
            'message', 0,
            'gift', v_gift,
            'mission', v_mission,
            'bonus', 0,
            'other', v_other
        ),
        'stats', jsonb_build_object(
            'video_call_count', v_video_calls,
            'video_call_seconds', v_video_seconds,
            'match_call_count', v_match_calls,
            'match_call_seconds', v_match_seconds,
            'avg_match_seconds', CASE
                WHEN v_match_calls > 0 THEN (v_match_seconds / v_match_calls)::bigint
                ELSE 0 END,
            'private_call_total', v_private_total,
            'private_call_answered', v_private_answered,
            'private_answer_rate', CASE
                WHEN v_private_total > 0
                THEN round((v_private_answered::numeric / v_private_total) * 100)
                ELSE 0 END
        )
    );
    RETURN result;
END;
$function$;
