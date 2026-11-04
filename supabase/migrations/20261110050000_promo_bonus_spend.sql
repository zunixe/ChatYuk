-- menyentuh: send_gift
-- menyentuh: send_coins
-- 2026-11-10: koin BONUS male bisa dipakai untuk call, gift, kirim koin &
-- langganan (bukan cuma fee match / 30 dtk pertama) — biaya promosi.
--   * Koin beli/penghasilan dipakai DULU; kekurangan ditambal bonus dengan
--     harga × app_settings.bonus_price_multiplier (default 3).
--   * Penerima tetap dapat `earned` (bisa ditarik) dihitung dari harga dasar.
--   * Biaya tunai promo dicatat di metadata ledger (`promo_idr`) dan dibatasi
--     app_settings.promo_budget_idr_monthly (default Rp300.000/bulan, WIB).
--     Hadiah misi female `earned` ikut memakan plafon yang sama.
--   * Hanya male terdaftar, punya device, device tidak dipakai akun lain.
--   * Plafon habis → kembali seperti sebelumnya (bonus hanya fee match &
--     30 detik pertama call).

alter table public.app_settings
  add column if not exists promo_budget_idr_monthly integer not null default 300000;

create index if not exists coin_ledger_promo_spend_idx
  on public.coin_ledger (created_at)
  where bucket = 'bonus' and amount < 0 and metadata ? 'promo_idr';
create index if not exists coin_ledger_mission_earned_idx
  on public.coin_ledger (created_at)
  where type = 'mission_reward' and bucket = 'earned';

create or replace function public._promo_multiplier()
returns integer
language sql
stable
security definer
set search_path to 'public'
as $function$
  select greatest(1, coalesce(bonus_price_multiplier, 3))
    from public.app_settings where id = 'global';
$function$;

-- Sisa plafon promo bulan ini (Rupiah tunai yang bisa ditarik female).
create or replace function public.promo_budget_left_idr()
returns numeric
language sql
stable
security definer
set search_path to 'public'
as $function$
  with m as (
    select (date_trunc('month', now() at time zone 'Asia/Jakarta')
              at time zone 'Asia/Jakarta') as start
  )
  select greatest(0,
           coalesce(s.promo_budget_idr_monthly, 0)
           - coalesce((select sum((l.metadata->>'promo_idr')::numeric)
                         from public.coin_ledger l, m
                        where l.bucket = 'bonus' and l.amount < 0
                          and l.metadata ? 'promo_idr'
                          and l.created_at >= m.start), 0)
           - coalesce((select sum(l.amount)
                         from public.coin_ledger l, m
                        where l.type = 'mission_reward' and l.bucket = 'earned'
                          and l.created_at >= m.start), 0)
             * coalesce(s.withdraw_rate_idr, 7)
             * (100 - coalesce(s.withdraw_fee_pct, 5)) / 100.0)
    from public.app_settings s
   where s.id = 'global';
$function$;

-- Boleh menambal pembayaran dengan bonus? (male terdaftar, device unik,
-- plafon masih ada). p_recipient dicadangkan untuk aturan penerima.
create or replace function public._promo_payer_ok(p_payer uuid, p_recipient uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_gender text;
  v_reg boolean;
begin
  if p_payer is null then
    return false;
  end if;
  if (select points_enabled from public.app_settings where id = 'global') is false then
    return false;
  end if;
  select gender, coalesce(is_registered, false) into v_gender, v_reg
    from public.profiles where id = p_payer;
  if v_gender is distinct from 'male' or not v_reg then
    return false;
  end if;
  if not exists (select 1 from public.user_devices
                  where user_id = p_payer and install_id <> 'unknown') then
    return false;
  end if;
  -- Device dipakai akun lain (termasuk penerima / akun anonim) → tidak.
  if exists (select 1 from public.user_devices d1
               join public.user_devices d2 on d2.install_id = d1.install_id
              where d1.user_id = p_payer and d2.user_id <> p_payer
                and d1.install_id <> 'unknown') then
    return false;
  end if;
  return public.promo_budget_left_idr() > 0;
end;
$function$;

-- Saldo yang bisa dipakai membayar (satuan harga dasar):
-- koin beli/penghasilan + bonus/multiplier (bila promo boleh, dibatasi plafon).
create or replace function public.yukcoin_spendable(p_user uuid, p_recipient uuid, p_host_pct integer)
returns integer
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_paid int := public.yukcoin_paid_total(p_user);
  v_bonus int;
  v_units int;
  v_per_unit numeric;
  s record;
begin
  if not public._promo_payer_ok(p_user, p_recipient) then
    return v_paid;
  end if;
  select coalesce(sum(amount), 0) into v_bonus
    from public.coin_ledger where user_id = p_user and bucket = 'bonus';
  v_units := greatest(v_bonus, 0) / public._promo_multiplier();
  select withdraw_rate_idr, withdraw_fee_pct into s
    from public.app_settings where id = 'global';
  v_per_unit := greatest(coalesce(p_host_pct, 0), 0) / 100.0
              * coalesce(s.withdraw_rate_idr, 7)
              * (100 - coalesce(s.withdraw_fee_pct, 5)) / 100.0;
  if v_per_unit > 0 then
    v_units := least(v_units, floor(public.promo_budget_left_idr() / v_per_unit)::int);
  end if;
  return v_paid + greatest(v_units, 0);
end;
$function$;

-- Debit pembayaran: koin beli/penghasilan dulu, kekurangan dari bonus
-- (× multiplier) bila promo boleh & plafon cukup. Return = saldo total.
create or replace function public.ledger_spend_promo(p_user uuid, p_type text, p_amount integer,
    p_ref text, p_recipient uuid, p_host_pct integer)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_paid int;
  v_short int;
  v_mult int;
  v_bonus int;
  v_need int;
  v_cost numeric;
  s record;
begin
  if p_amount is null or p_amount <= 0 then
    return public.wallet_sync_points(p_user);
  end if;
  perform pg_advisory_xact_lock(hashtext('wallet:' || p_user::text));

  v_paid := public.yukcoin_paid_total(p_user);
  if v_paid >= p_amount then
    return public.ledger_spend_paid(p_user, p_type, p_amount, p_ref);
  end if;

  v_short := p_amount - greatest(v_paid, 0);
  if not public._promo_payer_ok(p_user, p_recipient) then
    raise exception 'Not enough paid';
  end if;
  v_mult := public._promo_multiplier();
  v_need := v_short * v_mult;
  select coalesce(sum(amount), 0) into v_bonus
    from public.coin_ledger where user_id = p_user and bucket = 'bonus';
  select withdraw_rate_idr, withdraw_fee_pct into s
    from public.app_settings where id = 'global';
  v_cost := round(v_short * greatest(coalesce(p_host_pct, 0), 0) / 100.0
            * coalesce(s.withdraw_rate_idr, 7)
            * (100 - coalesce(s.withdraw_fee_pct, 5)) / 100.0, 2);
  -- Serialkan pemakaian plafon antar user.
  perform pg_advisory_xact_lock(hashtext('promo_budget'));
  if v_bonus < v_need or v_cost > public.promo_budget_left_idr() then
    raise exception 'Not enough paid';
  end if;

  if v_paid > 0 then
    perform public.ledger_spend_paid(p_user, p_type, v_paid, p_ref);
  end if;
  insert into public.coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
  values (p_user, 'bonus', p_type, -v_need, p_ref,
          jsonb_build_object('promo_base', v_short, 'multiplier', v_mult,
                             'promo_idr', v_cost, 'recipient', p_recipient));
  return public.wallet_sync_points(p_user);
end;
$function$;

revoke execute on function public._promo_multiplier() from public, anon, authenticated;
revoke execute on function public.promo_budget_left_idr() from public, anon, authenticated;
revoke execute on function public._promo_payer_ok(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.yukcoin_spendable(uuid, uuid, integer) from public, anon, authenticated;
revoke execute on function public.ledger_spend_promo(uuid, text, integer, text, uuid, integer) from public, anon, authenticated;

create or replace function public._charge_metered_core(p_caller uuid, p_feature text, p_ref text, p_units integer DEFAULT 1, p_recipient uuid DEFAULT NULL::uuid, p_ledger_type text DEFAULT NULL::text)
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
  -- 2026-11-10: + bonus male (harga ×multiplier, plafon promo) via
  -- ledger_spend_promo — lihat migrasi promo_bonus_spend.
  balance := public.yukcoin_spendable(p_caller, p_recipient, 100 - cut_pct);
  if balance < total then
    raise exception 'Koin beli/penghasilan tidak cukup (top-up dulu)'
      using errcode = '22023';
  end if;

  remaining := public.ledger_spend_promo(p_caller, v_ltype, total, p_ref,
    p_recipient, 100 - cut_pct);

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

create or replace function public._call_bill_as(p_call_id uuid, p_me uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := p_me;
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
  v_host_pct int;
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
  select 100 - coalesce(call_cut_pct, 70) into v_host_pct
    from app_settings where id = 'global';

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
  v_paid := public.yukcoin_spendable(v_payer, v_recipient, v_host_pct);
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
    v_paid := public.yukcoin_spendable(v_payer, v_recipient, v_host_pct);
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
      v_paid := public.yukcoin_spendable(v_payer, v_recipient, v_host_pct);
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

create or replace function public.send_gift(p_chat_id text, p_receiver_id uuid, p_gift_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int;
  my_name text; my_gender text; am_registered boolean;
  n int; cut int; net int;
  paid int; remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  -- 2026-11-10: serialkan debit per user (sama dgn ledger_spend_paid dst);
  -- juga menutup balapan cek batas transaksi/jam.
  perform pg_advisory_xact_lock(hashtext('wallet:' || uid::text));
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;
  select points_enabled, coalesce(gift_cut_pct,30)
    into points_on, cut_pct from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;
  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;
  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;
  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins;
  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;
  if exists (select 1 from public.blocks b
      where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
         or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- 2026-10-31: gift WAJIB pakai koin beli/penghasilan (topup + earned).
  -- Koin gratis (`bonus`) TIDAK boleh dipakai — mencegah koin gratis male
  -- berubah menjadi saldo withdrawable female (rugi platform).
  -- 2026-11-10: male boleh menambal dengan bonus (harga ×multiplier,
  -- plafon promo) — ledger_spend_promo.
  paid := public.yukcoin_spendable(uid, p_receiver_id, 100 - cut_pct);

  if paid < n then
    raise exception 'Gift membutuhkan koin beli/penghasilan (top-up dulu)'
      using errcode = '22023';
  end if;

  remaining := public.ledger_spend_promo(uid, 'gift_sent', n, p_chat_id,
    p_receiver_id, 100 - cut_pct);

  -- Platform ambil cut; penerima SELALU bucket `earned`.
  cut := (n * cut_pct) / 100;
  net := n - cut;

  if net > 0 then
    perform public.ledger_credit(p_receiver_id, 'earned', 'gift_recv', net,
      p_chat_id, jsonb_build_object('gift', p_gift_id, 'from', uid, 'tier', 'paid'));
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
              jsonb_build_object('gift', p_gift_id, 'gross', n, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n, jsonb_build_object('gift', p_gift_id, 'tier', 'paid')),
           (p_receiver_id, 'gift_recv', net,
            jsonb_build_object('gift', p_gift_id, 'tier', 'paid'));

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut, 'tier', 'paid');
end; $function$;

create or replace function public.send_coins(p_chat_id text, p_receiver_id uuid, p_amount integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
  v_cut_pct int; v_cut int; v_net int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;

  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- B1: potongan platform (default 30%). Penerima menerima NET ke
  -- `earned` — masih bisa di-withdraw, tapi hasil "pencucian" send_coins
  -- kini dipotong seperti gift sehingga refund-fraud tidak lagi gratis.
  select coalesce(coin_send_cut_pct, 30) into v_cut_pct
    from app_settings where id = 'global';

  -- Koin beli/penghasilan dulu; male boleh menambal dengan bonus
  -- (×multiplier, plafon promo) — ledger_spend_promo (2026-11-10).
  remaining := public.ledger_spend_promo(uid, 'coin_sent', p_amount, p_chat_id,
    p_receiver_id, 100 - v_cut_pct);
  v_cut := (p_amount * v_cut_pct) / 100;
  v_net := p_amount - v_cut;

  perform public.ledger_credit(p_receiver_id, 'earned', 'coin_received', v_net,
    p_chat_id, jsonb_build_object('from', uid,
      'gross', p_amount, 'cut', v_cut, 'pct', v_cut_pct));

  if v_cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
    values ('coin_send_cut', v_cut, uid, p_receiver_id, p_chat_id,
            jsonb_build_object('gross', p_amount, 'pct', v_cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', v_net);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
    'sent', p_amount, 'received', v_net, 'cut_pct', v_cut_pct);
end; $function$;

create or replace function public.subscribe_creator(p_creator uuid, p_periods integer DEFAULT 1, p_expected_price integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); price int; cut_pct int; duration_days int; periods int;
  points_on boolean; am_registered boolean; remaining int; cost int; cut int; net int;
  expire timestamptz;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_creator is null or p_creator = me then raise exception 'Invalid creator'; end if;

  select is_registered into am_registered from profiles where id = me;
  if am_registered is not true then raise exception 'Subscriber must be registered'; end if;

  select subscription_price into price from profiles where id = p_creator;
  if price is null or price <= 0 then raise exception 'Not a paid creator'; end if;
  -- 2026-11-10: harga yang dilihat user di layar HARUS sama — kreator tak
  -- bisa menaikkan harga tepat sebelum user menekan Langganan.
  if p_expected_price is not null and p_expected_price <> price then
    raise exception 'PRICE_CHANGED';
  end if;

  select points_enabled, subscribe_cut_pct, subscription_duration_days
    into points_on, cut_pct, duration_days from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  periods := greatest(coalesce(p_periods, 1), 1);
  if periods > 12 then raise exception 'Invalid periods'; end if;

  cost := price * periods;
  cut := (cost * cut_pct) / 100;
  net := cost - cut;

  -- Koin beli/penghasilan dulu; male boleh menambal dengan bonus
  -- (×multiplier, plafon promo) — ledger_spend_promo (2026-11-10).
  remaining := public.ledger_spend_promo(me, 'subscribe', cost, p_creator::text,
    p_creator, 100 - cut_pct);

  -- Perpanjang / buat subscription.
  select expires_at into expire from subscriptions
    where subscriber_id = me and creator_id = p_creator;
  if expire is null or expire < now() then
    expire := now();
  end if;
  expire := expire + make_interval(days => duration_days * periods);

  insert into subscriptions (subscriber_id, creator_id, price, starts_at, expires_at)
    values (me, p_creator, price, now(), expire)
    on conflict (subscriber_id, creator_id)
    do update set price = excluded.price, expires_at = excluded.expires_at;

  if net > 0 then
    perform public.ledger_credit(p_creator, 'earned', 'subscribe_income', net,
      me::text, jsonb_build_object('subscriber', me, 'periods', periods));
  end if;
  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('subscribe_cut', cut, me, p_creator, p_creator::text,
              jsonb_build_object('gross', cost, 'net', net, 'pct', cut_pct, 'periods', periods));
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (me, 'subscribe', -cost, jsonb_build_object('creator', p_creator, 'periods', periods));

  return jsonb_build_object('ok', true, 'points', remaining, 'expires_at', expire,
    'net', net, 'cut', cut);
end; $function$;

create or replace function public.get_wallet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b int; t int; e int;
begin
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = auth.uid();
  return jsonb_build_object(
    'bonus', b, 'topup', t, 'earned', e,
    'total', b + t + e,
    'withdrawable', e,
    -- 2026-11-10: bonus bisa menambal call/gift/kirim/langganan (×mult).
    'promo_ok', public._promo_payer_ok(auth.uid(), null),
    'bonus_multiplier', public._promo_multiplier()
  );
end; $function$;

create or replace function public._mission_payout_eligible(p_uid uuid, p_ip text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.user_devices
                  where user_id = p_uid and install_id <> 'unknown') then
    return 'no_device';
  end if;
  if exists (select 1 from public.user_devices d
               join public.mission_payout_devices o on o.install_id = d.install_id
              where d.user_id = p_uid and o.user_id <> p_uid) then
    return 'shared_device';
  end if;
  if p_ip is not null and exists (
       select 1 from public.coin_ledger l
        where l.type = 'mission_reward' and l.bucket = 'earned'
          and l.metadata->>'ip' = p_ip
          and l.created_at > now() - interval '24 hours'
          and l.user_id <> p_uid) then
    return 'shared_ip';
  end if;
  -- 2026-11-10: plafon promo bulanan habis → bonus.
  if public.promo_budget_left_idr() <= 0 then
    return 'promo_budget';
  end if;
  return null;
end;
$function$;
