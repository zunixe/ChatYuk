-- ============================================================
-- ChatYuk — Coin untuk nelp (TANPA gratis) + fix cell ekonom + welcome bonus
--
-- Keputusan produk (Okt 2026):
--   1. Nelp MURNI pakai coin dari menit pertama (tidak ada kuota gratis).
--   2. Tarif call: audio 6 / video 20 coin per menit.
--   3. Saldo awal user baru = WELCOME BONUS bertahap:
--        anon   = 100 coin (cukup video 5 menit)
--        register (email terverifikasi) = 100 coin lagi → total 200.
--        Register langsung (tanpa fase anon) → dapat full 200.
--   4. Anti-farming: bonus HANYA sekali per install_id (device fisik) +
--      limit jumlah klaim per IP per hari. Klaim lewat edge function
--      `welcome-bonus` (IP ditangkap server-side, bisa dipercaya).
--
-- File ini (R1):
--   a. buang kolom/fungsi kuota gratis call
--   b. rewrite call_billing_tick (tanpa gratis, return per_minute)
--   c. tutup celah: charge_metered jangan bisa dipanggil user langsung
--   d. tabel bonus_claims + RPC credit_welcome_bonus (service_role)
--
-- Idempotent.
-- ============================================================

-- ──────────────────────────────────────────────
-- a. Buang kuota gratis call (tidak dipakai lagi)
-- ──────────────────────────────────────────────
-- SAFE: kolom kuota-gratis-call tak lagi dipakai (nelp murni coin); tak ada
-- fitur lain membaca kolom ini — hanya call_billing_tick (di-rewrite di bawah).
alter table public.profiles
  drop column if exists call_free_audio_seconds_today, -- SAFE: kuota gratis call dihapus
  drop column if exists call_free_video_seconds_today, -- SAFE: kuota gratis call dihapus
  drop column if exists call_free_date; -- SAFE: kuota gratis call dihapus

-- SAFE: app_settings.call_free_minutes_daily tak lagi dipakai — hanya
-- call_free_limit_sec/call_billing_tick (dihapus/di-rewrite di bawah).
alter table public.app_settings
  drop column if exists call_free_minutes_daily; -- SAFE: kuota gratis call dihapus

-- Fungsi helper kuota gratis — tak lagi relevan.
drop function if exists public.call_free_limit_sec(); -- SAFE: helper kuota gratis yang dihapus

-- ──────────────────────────────────────────────
-- b. Rewrite call_billing_tick — TANPA kuota gratis
--    Server otoritatif: elapsed dari answered_at. Idempoten per menit.
--    Return {ok, can_continue, billed_minutes, charged_total, remaining,
--            per_minute, reason?}.
-- ──────────────────────────────────────────────
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

  -- Gate publish (admin selalu boleh). Bila OFF → jangan tagih.
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;

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

-- ──────────────────────────────────────────────
-- c. Tutup celah: charge_metered TIDAK boleh dipanggil user langsung
--    (param p_caller → bisa mendebit coin orang lain). Hanya service_role;
--    call_billing_tick & gate_feature memanggilnya sebagai definer.
-- ──────────────────────────────────────────────
revoke execute on function public.charge_metered(uuid, text, text, int, uuid)
  from public, anon, authenticated;
grant execute on function public.charge_metered(uuid, text, text, int, uuid)
  to service_role;

-- ──────────────────────────────────────────────
-- d. Config welcome bonus
-- ──────────────────────────────────────────────
alter table public.app_settings
  add column if not exists welcome_anon_coins          int not null default 100,
  add column if not exists welcome_register_coins      int not null default 100,
  add column if not exists welcome_max_claims_per_ip_day int not null default 3;

-- ──────────────────────────────────────────────
-- e. Tabel klaim bonus (anti-farming)
-- ──────────────────────────────────────────────
create table if not exists public.bonus_claims (
  install_id text not null,
  kind       text not null check (kind in ('anon','register')),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  ip         text,
  created_at timestamptz not null default now(),
  primary key (install_id, kind)
);
create index if not exists idx_bonus_claims_ip
  on public.bonus_claims(ip, kind, created_at desc);

alter table public.bonus_claims enable row level security;
-- SAFE: tabel baru (idempotent). Baca hanya milik sendiri / admin; tulis via RPC.
drop policy if exists bonus_claims_select_own on public.bonus_claims; -- SAFE: tabel baru v2; baca hanya baris sendiri / admin
create policy bonus_claims_select_own on public.bonus_claims -- SAFE: tabel baru; baca klaim sendiri (RLS owner)
  for select using (
    user_id = auth.uid()
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );
revoke insert, update, delete on public.bonus_claims from anon, authenticated; -- SAFE: tulis hanya via RPC security definer
grant select on public.bonus_claims to authenticated; -- SAFE: baca klaim sendiri (RLS owner)

-- ──────────────────────────────────────────────
-- f. RPC credit_welcome_bonus (service_role) — 3 lapis anti-farming
--    Return {ok, granted, coins, total, reason?}
-- ──────────────────────────────────────────────
create or replace function public.credit_welcome_bonus(
  p_user uuid, p_install_id text, p_kind text, p_ip text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  coins int; max_ip int; ip_count int; tot int; existing int;
begin
  if p_user is null then raise exception 'Missing user'; end if;
  if p_kind not in ('anon','register') then
    raise exception 'Invalid kind: %', p_kind;
  end if;
  if p_install_id is null or length(trim(p_install_id)) < 6 then
    raise exception 'Invalid install_id';
  end if;

  select case p_kind
           when 'anon' then coalesce(welcome_anon_coins,100)
           else coalesce(welcome_register_coins,100) end,
         coalesce(welcome_max_claims_per_ip_day, 3)
    into coins, max_ip
    from app_settings where id = 'global';

  -- Lapis 1: install_id + kind sudah pernah klaim?
  select count(*) into existing from public.bonus_claims
    where install_id = p_install_id and kind = p_kind;
  if existing > 0 then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'already_claimed', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;

  -- Lapis 2: limit klaim per IP / 24 jam (bila IP tersedia).
  if p_ip is not null and length(trim(p_ip)) > 0 then
    select count(*) into ip_count from public.bonus_claims
      where ip = p_ip and kind = p_kind
        and created_at > now() - interval '24 hours';
    if ip_count >= max_ip then
      return jsonb_build_object('ok', true, 'granted', false,
        'reason', 'ip_limit', 'coins', 0,
        'total', public.yukcoin_total(p_user));
    end if;
  end if;

  -- Beri bonus (semua ke bucket 'bonus').
  insert into public.bonus_claims(install_id, kind, user_id, ip)
    values (p_install_id, p_kind, p_user, nullif(trim(coalesce(p_ip,'')), ''))
    on conflict (install_id, kind) do nothing;
  if not found then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'race', 'coins', 0, 'total', public.yukcoin_total(p_user));
  end if;

  tot := public.ledger_credit(p_user, 'bonus', 'welcome_' || p_kind, coins,
           null, jsonb_build_object('install_id', p_install_id, 'ip', p_ip));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, 'welcome_' || p_kind, coins,
            jsonb_build_object('install_id', p_install_id));

  return jsonb_build_object('ok', true, 'granted', true, 'coins', coins,
    'total', tot);
end; $$;
revoke execute on function public.credit_welcome_bonus(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.credit_welcome_bonus(uuid, text, text, text)
  to service_role;
