-- ============================================================
-- ChatYuk Coin Engine v1 — config + RPC metered generik + feature flags
--
-- Konteks: sistem poin lama memberi BANYAK poin gratis (login streak,
-- one_time_bonus, room_read, new_chat, dst.) → inflasi, tidak ada revenue.
-- Keputusan produk (Okt 2026):
--   1. HAPUS semua poin gratis; saldo awal 0.
--   2. Coin masuk HANYA dari topup Google Play Billing (+ 30% income call).
--   3. Fitur berbayar: call audio/video (per menit), filter gender &
--      orang sekitar (per akses HARIAN).
--   4. Call: 5 menit gratis / hari / user PER TIPE (audio & video terpisah).
--   5. Split call: 70% platform / 30% penerima (coin, bukan uang).
--   6. Saldo habis di tengah call → call diputus (server otoritatif).
--   7. Semua angka configurable dari admin (app_settings), bukan hardcode.
--
-- File ini: kolom config + RPC engine (charge_metered, call_billing_tick,
-- gate_feature, feature_enabled_for). Faucet lama dimatikan di file migrasi
-- terpisah (20261001010000_disable_free_points.sql).
--
-- Idempotent (add column if not exists / create or replace).
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Kolom konfigurasi ekonomi (app_settings)
-- ──────────────────────────────────────────────
alter table public.app_settings
  add column if not exists call_audio_cost_per_min  int  not null default 6,
  add column if not exists call_video_cost_per_min  int  not null default 20,
  add column if not exists call_free_minutes_daily  int  not null default 5,
  add column if not exists call_cut_pct             int  not null default 70,
  add column if not exists filter_gender_cost       int  not null default 15,
  add column if not exists nearby_cost              int  not null default 25,
  -- Registry tarif fitur berbayar generik (dipakai fitur lain nanti):
  --   { "<feature>": {"unit_cost":N,"cut_pct":M,"model":"per_min"|"per_day"} }
  add column if not exists metered_pricing jsonb not null default jsonb_build_object(
    'call_audio',    jsonb_build_object('unit_cost',6, 'cut_pct',70,'model','per_min'),
    'call_video',    jsonb_build_object('unit_cost',20,'cut_pct',70,'model','per_min'),
    'filter_gender', jsonb_build_object('unit_cost',15,'cut_pct',0, 'model','per_day'),
    'nearby',        jsonb_build_object('unit_cost',25,'cut_pct',0, 'model','per_day')
  ),
  -- Feature flags: fitur tersembunyi sampai admin "publish".
  --   { "<feature>": {"published": bool} }
  add column if not exists feature_flags jsonb not null default jsonb_build_object(
    'call_billing',       jsonb_build_object('published', false),
    'gender_filter_paid', jsonb_build_object('published', false),
    'nearby_paid',        jsonb_build_object('published', false),
    'play_topup',         jsonb_build_object('published', false)
  );

-- ──────────────────────────────────────────────
-- 2. Kolom counter di profiles
-- ──────────────────────────────────────────────
-- Kuota gratis call dihitung PER TIPE (audio & video terpisah), reset harian
-- TZ Asia/Jakarta. Tanggal pakai kolom sendiri (call_free_date) supaya reset
-- TIDAK bergantung daily_login_bonus (yang kini dimatikan).
alter table public.profiles
  add column if not exists call_free_audio_seconds_today int not null default 0,
  add column if not exists call_free_video_seconds_today int not null default 0,
  add column if not exists call_free_date date;

-- ──────────────────────────────────────────────
-- 3. RPC: feature_enabled_for — gerbang publish per fitur
--    True bila flag published = true, ATAU pemanggil admin (test).
-- ──────────────────────────────────────────────
create or replace function public.feature_enabled_for(p_feature text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v boolean;
begin
  select (feature_flags -> p_feature ->> 'published')::boolean
    into v from app_settings where id = 'global';
  if v is true then return true; end if;
  -- Admin selalu boleh (test di build adminProd sebelum publish).
  return coalesce(auth.email(), '') = 'zunixe@gmail.com';
end; $$;
revoke execute on function public.feature_enabled_for(text) from public, anon;
grant execute on function public.feature_enabled_for(text) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 4. RPC inti: charge_metered — SATU jalur potong coin generik
--    p_units: jumlah unit yang ditagih (mis. 1 menit).
--    Return {ok, charged, cut, net, remaining, caller}.
--    Raise 'YukCoin tidak cukup' bila saldo < total.
--    Bila p_recipient diberikan & cut_pct > 0 → 30% (1-cut) ke penerima.
-- ──────────────────────────────────────────────
create or replace function public.charge_metered(
  p_caller uuid,
  p_feature text,
  p_ref text,
  p_units int default 1,
  p_recipient uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb; unit_cost int; cut_pct int;
  total int; cut int; net int; remaining int; balance int;
begin
  if p_caller is null then raise exception 'Not authenticated'; end if;
  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  select metered_pricing -> p_feature into cfg
    from app_settings where id = 'global';
  if cfg is null then
    raise exception 'Unknown metered feature: %', p_feature;
  end if;
  unit_cost := coalesce((cfg->>'unit_cost')::int, 0);
  cut_pct   := coalesce((cfg->>'cut_pct')::int, 0);

  total := unit_cost * p_units;
  if total <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  balance := public.yukcoin_total(p_caller);
  if balance < total then
    raise exception 'YukCoin tidak cukup';
  end if;

  -- Potong dari saldo penelepon (semua bucket boleh dipakai — ekosistem
  -- coin tertutup: coin dari topup & dari income call sama-sama bisa dipakai).
  remaining := public.ledger_spend(p_caller, p_feature, total, p_ref);

  -- Split ke penerima (mis. pemilik call). Platform ambil cut_pct.
  cut := (total * cut_pct) / 100;
  net := total - cut;
  if p_recipient is not null and p_recipient <> p_caller and net > 0 then
    perform public.ledger_credit(p_recipient, 'earned', p_feature || '_income',
      net, p_ref, jsonb_build_object('from', p_caller, 'feature', p_feature,
      'gross', total, 'cut', cut));
    insert into public.point_events (user_id, event, amount, metadata)
      values (p_recipient, p_feature || '_income', net,
              jsonb_build_object('from', p_caller, 'ref', p_ref));
  end if;

  -- Catat revenue platform (cut).
  if cut > 0 then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (p_feature, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, p_feature, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $$;
revoke execute on function public.charge_metered(uuid, text, text, int, uuid) from public, anon;
grant execute on function public.charge_metered(uuid, text, text, int, uuid) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 5. RPC: call_billing_tick — tagih call per menit (dipanggil client)
--    Server OTORITATIF: hitung menit berbayar dari answered_at (bukan
--    laporan client). Idempoten per menit via yukcoin_consumptions.
--    Return {ok, billed_minutes, free_remaining_sec, charged_total,
--            remaining, can_continue}.
-- ──────────────────────────────────────────────
create or replace function public.call_billing_tick(p_call_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c record;
  feat text; unit_cost int;
  free_limit_sec int; used_sec int; free_used int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  afford int; charge_n int;
  remaining int; free_remaining int;
  today date;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  -- Gate publish (admin selalu boleh).
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'free_remaining_sec', 0, 'charged_total', 0);
  end if;

  -- Call harus sudah dijawab.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'free_remaining_sec', public.call_free_limit_sec(),
      'charged_total', 0, 'remaining', public.yukcoin_total(me));
  end if;

  feat := case c.call_type when 'audio' then 'call_audio' else 'call_video' end;
  select case c.call_type
           when 'audio' then call_audio_cost_per_min
           else call_video_cost_per_min end,
         coalesce(call_free_minutes_daily, 5) * 60
    into unit_cost, free_limit_sec
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);
  free_limit_sec := coalesce(free_limit_sec, 300);

  -- Reset kuota harian bila ganti hari (TZ Asia/Jakarta).
  today := (now() at time zone 'Asia/Jakarta')::date;
  update public.profiles
    set call_free_audio_seconds_today = 0,
        call_free_video_seconds_today = 0,
        call_free_date = today
  where id = me and (call_free_date is null or call_free_date <> today);

  -- Detik elapsed dihitung SERVER-SIDE dari answered_at (anti-tamper client).
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);

  -- Kuota gratis per tipe (audio & video terpisah).
  select case c.call_type
           when 'audio' then call_free_audio_seconds_today
           else call_free_video_seconds_today end
    into used_sec
    from public.profiles where id = me;
  used_sec := coalesce(used_sec, 0);
  free_used := greatest(0, least(used_sec, free_limit_sec));

  -- Menit berbayar = menit yang melewati kuota gratis.
  billable_minutes := greatest(0, ((elapsed_sec - free_limit_sec) + 59) / 60);

  -- Sudah ditagih berapa menit untuk call ini (idempoten).
  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = me and feature = feat and ref_id = p_call_id::text;

  to_bill := greatest(0, billable_minutes - already_billed);
  remaining := public.yukcoin_total(me);

  if to_bill > 0 then
    -- Saldo < 1 unit → tidak bisa lanjut (putus).
    if remaining < unit_cost then
      free_remaining := greatest(0, free_limit_sec - free_used);
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed, 'free_remaining_sec', free_remaining,
        'charged_total', already_billed * unit_cost, 'remaining', remaining,
        'reason', 'insufficient');
    end if;

    -- Tagih sebanyak yang sanggup (mencegah saldo minus), catat per menit
    -- agar idempoten & bisa putus di tengah bila saldo habis.
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
      free_remaining := greatest(0, free_limit_sec - free_used);
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed, 'free_remaining_sec', free_remaining,
        'charged_total', already_billed * unit_cost, 'remaining', remaining,
        'reason', 'insufficient');
    end if;
  end if;

  free_remaining := greatest(0, free_limit_sec - free_used);
  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed, 'free_remaining_sec', free_remaining,
    'charged_total', already_billed * unit_cost, 'remaining', remaining);
end; $$;
revoke execute on function public.call_billing_tick(uuid) from public, anon;
grant execute on function public.call_billing_tick(uuid) to authenticated, service_role;

-- Helper: limit kuota gratis (detik) — dipakai call_billing_tick & UI.
create or replace function public.call_free_limit_sec()
returns int language sql stable security definer set search_path = public as $$
  select coalesce(call_free_minutes_daily, 5) * 60
    from app_settings where id = 'global';
$$;
revoke execute on function public.call_free_limit_sec() from public, anon;
grant execute on function public.call_free_limit_sec() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 6. RPC: gate_feature — potong akses HARIAN (filter gender, nearby)
--    Idempoten per hari: bayar sekali, bebas seharian. Tandai via
--    yukcoin_consumptions (ref = feature + ':' + tanggal).
--    Return {ok, charged, already, remaining}.
-- ──────────────────────────────────────────────
create or replace function public.gate_feature(
  p_feature text,
  p_price_feature text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  cfg jsonb; unit_cost int;
  rkey text; already int; bal int; remaining int;
  today date;
begin
  if me is null then raise exception 'Not authenticated'; end if;

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
end; $$;
revoke execute on function public.gate_feature(text, text) from public, anon;
grant execute on function public.gate_feature(text, text) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 7. RPC: status harga fitur (untuk UI)
-- ──────────────────────────────────────────────
create or replace function public.metered_pricing_public()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return (select jsonb_build_object(
    'call_audio_cost_per_min', call_audio_cost_per_min,
    'call_video_cost_per_min', call_video_cost_per_min,
    'call_free_minutes_daily', call_free_minutes_daily,
    'filter_gender_cost', filter_gender_cost,
    'nearby_cost', nearby_cost
  ) from app_settings where id = 'global');
end; $$;
revoke execute on function public.metered_pricing_public() from public, anon;
grant execute on function public.metered_pricing_public() to authenticated, service_role;
