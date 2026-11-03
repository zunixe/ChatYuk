-- ══════════════════════════════════════════════════════════════════════
-- Fase A: tutup kebocoran uang YukCoin (review ekonomi 2026-11-06).
--
-- A1. REVOKE: _charge_metered_core & touch_call bisa dieksekusi anon/
--     authenticated secara langsung (terkonfirmasi live) → siapa pun bisa
--     menguras koin user lain ke akun female-nya lalu withdraw.
--     yukcoin_paid_total dibatasi ke pemiliknya (bocor saldo orang lain).
-- A2. call_billing_tick: kunci baris call (FOR UPDATE), cap elapsed ke
--     ended_at, dan HANYA payer yang memicu charge — tick recipient jadi
--     read-only (tetap mengembalikan income_total untuk UI).
-- A3. Trigger calls: klien (authenticated/anon) tidak bisa mengubah
--     kind / answered_at / media_connected_at; insert hanya direct+ringing.
--     Tulis lewat fungsi DEFINER (random_match_join, touch_call, sweep)
--     berjalan sebagai owner (postgres) → tidak terpengaruh.
-- A4. Idempotensi: unique index per menit & connect-fee di
--     yukcoin_consumptions; advisory lock 'wallet:<uid>' di
--     ledger_spend_paid & _spend_yukcoin_core (sama namespace dgn
--     ledger_spend/ledger_spend_earned → semua debit per-user terserial);
--     trigger CHECK saldo bucket tidak boleh negatif.
-- A5. Cron harian economy_invariant_check → economy_invariant_log;
--     bersihkan admin_test_grant (reversal ledger, ledger append-only).
-- ══════════════════════════════════════════════════════════════════════

-- ── A1a. Privilege ───────────────────────────────────────────────────────
revoke execute on function public._charge_metered_core(uuid, text, text, integer, uuid, text)
  from public, anon, authenticated;
-- touch_call masih dipakai client authenticated (heartbeat+stamp connect);
-- cukup cabut dari anon & public.
revoke execute on function public.touch_call(uuid, boolean) from public, anon;
-- Saldo paid orang lain tidak perlu bisa dibaca client lain. Klien tidak
-- pernah memanggil rpc ini langsung (grep lib/ → 0) — pemakaian internal
-- lewat fungsi definer tetap jalan (owner=postgres).
revoke execute on function public.yukcoin_paid_total(uuid)
  from public, anon, authenticated;

-- ── A2. call_billing_tick: row-lock + ended-cap + payer-only charge ────────
-- menyentuh: call_billing_tick
create or replace function public.call_billing_tick(p_call_id uuid)
returns jsonb
language plpgsql security definer set search_path to 'public'
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

  -- A2a: KUNCI baris call — dua tick bersamaan (payer+callee / dua device)
  -- terserial → tidak ada double-charge.
  select * into c from public.calls where id = p_call_id for update;
  if not found then raise exception 'Call not found'; end if;

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
  v_end   := case when c.ended_at is not null then c.ended_at else now() end;

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
    v_anchor := case when c.kind = 'random'
                     then coalesce(c.media_connected_at, c.answered_at)
                     else c.answered_at end;
    elapsed_sec := greatest(0, floor(extract(epoch from (v_end - v_anchor)))::int);
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

-- ── A3. Guard kolom billing di tabel calls ───────────────────────────────
-- Klien menulis langsung ke calls (status/ended_at sah). Kolom yang
-- menentukan JUMLAH tagihan tidak boleh disentuh klien:
--   kind (bikin call 'random' palsu), answered_at (backdate → menit ekstra),
--   media_connected_at (server-set via touch_call).
-- Trigger berjalan sebagai role pemanggil; definer function dieksekusi
-- sebagai owner (postgres) → lolos.
create or replace function public.calls_client_guard()
returns trigger language plpgsql as $$
begin
  -- Role PostgREST: 'authenticated'/'anon' = tulis langsung dari client.
  -- Fungsi DEFINER (random_match_join, touch_call, admin_sweep_calls)
  -- berjalan sebagai owner 'postgres' → tidak terjaga trigger ini.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.kind is distinct from 'direct'
       or new.status is distinct from 'ringing'
       or new.answered_at is not null
       or new.media_connected_at is not null then
      raise exception 'client may only insert ringing direct calls'
        using errcode = '42501';
    end if;
    return new;
  end if;
  -- UPDATE
  if new.kind is distinct from old.kind then
    raise exception 'calls.kind is immutable' using errcode = '42501';
  end if;
  if new.media_connected_at is distinct from old.media_connected_at then
    raise exception 'calls.media_connected_at is server-managed'
      using errcode = '42501';
  end if;
  if new.answered_at is distinct from old.answered_at then
    -- boleh SET SEKALI saat menjawab; tidak boleh lampau (≥ created_at,
    -- toleransi skew device) maupun mengubah setelah terisi.
    if old.answered_at is not null or new.answered_at is null
       or new.answered_at < old.created_at - interval '10 seconds'
       or new.answered_at > now() + interval '10 minutes' then
      raise exception 'calls.answered_at is server-managed'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists calls_client_guard_trg on public.calls;
create trigger calls_client_guard_trg
  before insert or update on public.calls
  for each row execute function public.calls_client_guard();

-- ── A4a. Unique index konsumsi ───────────────────────────────────────────
-- Dedup sisa double-charge lama (menit sama tertagih 2x) sebelum index.
-- Refund: kembalikan biaya baris duplikat ke bucket yang sama (reversal
-- ledger — append-only), recipient income dibiarkan (platform menyerap).
do $$
declare
  r record;
begin
  for r in (
    select d.id as dup_id, d.user_id, d.feature, d.ref_id, d.cost,
           d.metadata->>'minute' as minute
      from public.yukcoin_consumptions d
     where d.metadata ? 'minute'
       and exists (
         select 1 from public.yukcoin_consumptions x
          where x.id < d.id and x.user_id = d.user_id
            and x.feature = d.feature and x.ref_id = d.ref_id
            and x.metadata->>'minute' = d.metadata->>'minute')
  ) loop
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (r.user_id, 'earned', 'billing_dup_reversal', r.cost, r.ref_id,
              jsonb_build_object('dup_consumption', r.dup_id,
                                 'minute', r.minute, 'feature', r.feature));
    delete from public.yukcoin_consumptions where id = r.dup_id;
  end loop;
end $$;

create unique index if not exists yukcoin_consumptions_minute_uk
  on public.yukcoin_consumptions
  (user_id, feature, ref_id, ((metadata->>'minute')::int))
  where metadata ? 'minute';

-- ── A4b. Advisory lock pada debit ledger ─────────────────────────────────
-- ledger_spend/ledger_spend_earned sudah memegang 'wallet:<uid>' — samakan
-- di dua jalur debit lain supaya SEMUA penarikan per-user terserial.
-- menyentuh: ledger_spend_paid
create or replace function public.ledger_spend_paid(p_user uuid, p_type text,
    p_amount integer, p_ref text default null::text)
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare t int; e int; need int; take int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;

  perform pg_advisory_xact_lock(hashtext('wallet:' || p_user::text));

  select coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into t, e from coin_ledger where user_id = p_user;
  if (t + e) < p_amount then raise exception 'Not enough paid'; end if;

  need := p_amount;
  take := least(t, need);
  if take > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'topup',p_type,-take,p_ref);
    need := need - take;
  end if;
  if need > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'earned',p_type,-need,p_ref);
  end if;
  return public.wallet_sync_points(p_user);
end; $function$;

-- ── A4c. CHECK: bucket tidak boleh negatif ───────────────────────────────
-- Constraint tidak bisa mengecek agregat → trigger. Dengan advisory lock
-- di seluruh jalur debit, dua transaksi debit per-user tak bisa berpacu
-- melewati cek ini.
create or replace function public.coin_ledger_nonneg_guard()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare v_sum bigint;
begin
  if new.amount < 0 then
    select coalesce(sum(amount),0) into v_sum
      from public.coin_ledger
     where user_id = new.user_id and bucket = new.bucket;
    if v_sum < 0 then
      raise exception 'Saldo % tidak cukup (akan negatif)', new.bucket
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists coin_ledger_nonneg_trg on public.coin_ledger;
create trigger coin_ledger_nonneg_trg
  after insert on public.coin_ledger
  for each row execute function public.coin_ledger_nonneg_guard();

-- ── A5a. Cron harian invariant check → tabel log ─────────────────────────
create table if not exists public.economy_invariant_log (
  id bigint generated always as identity primary key,
  run_at timestamptz not null default now(),
  check_name text not null,
  user_id uuid,
  expected bigint,
  actual bigint,
  detail text
);
alter table public.economy_invariant_log enable row level security;
-- Tak ada policy → client tak bisa baca/tulis; admin via service/owner.

create or replace function public.economy_invariant_cron()
returns int language plpgsql security definer set search_path to 'public'
as $$
declare v_n int;
begin
  insert into public.economy_invariant_log
        (check_name, user_id, expected, actual, detail)
    select check_name, user_id, expected, actual, detail
      from public.economy_invariant_check(500);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise warning 'economy_invariant_check: % pelanggaran', v_n;
  end if;
  return v_n;
end;
$$;

select cron.schedule('economy-invariant-daily', '25 3 * * *',
  'select public.economy_invariant_cron()')
where not exists (
  select 1 from cron.job where jobname = 'economy-invariant-daily');

-- ── A5b. Bersihkan admin_test_grant (reversal, ledger append-only) ────────
-- 1.000 koin 'earned' hasil test di akun male terdaftar bisa dikirim ke
-- female lalu di-withdraw. Debit sisa yang masih ada (max grant, tak boleh
-- melampaui saldo earned-nya — CHECK nonneg aktif).
insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
select v.uid, 'earned', 'admin_test_grant_reversal',
       -least(1000, v.earned_now), 'manual-test',
       jsonb_build_object('reversal_of', 'admin_test_grant',
                          'granted', 1000, 'reversed', least(1000, v.earned_now))
  from (
    select cl.user_id as uid,
           coalesce(sum(cl.amount) filter (where cl.bucket = 'earned'),0)::int
             as earned_now
      from public.coin_ledger cl
     where cl.user_id in (
       select user_id from public.coin_ledger
        where type = 'admin_test_grant' and bucket = 'earned' and amount > 0)
     group by cl.user_id
  ) v
 where v.earned_now > 0;
