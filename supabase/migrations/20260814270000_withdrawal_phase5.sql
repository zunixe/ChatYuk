-- ============================================================
-- ChatYuk Wallet FASE 5 — Withdrawal (Pencairan)
--
-- Model B payout: platform beli kembali coin 'earned' dari user
-- yang KYC-nya sudah disetujui, dengan rate Rp/coin (default 7).
--   - Saat request: debit 'earned' (hold) → withdrawal_requests 'pending'.
--   - Admin bayar manual (QRIS/bank/ewallet) lalu tandai 'paid' (+tx_id).
--   - Admin tolak → refund 'earned' (credit kembali).
-- Syarat: KYC approved, >= withdraw_min_coins, sistem poin ON.
-- Hanya bucket 'earned' yang bisa dicairkan (bonus & topup tidak).
-- ============================================================

-- Konfigurasi withdrawal di app_settings
alter table public.app_settings
  add column if not exists withdraw_rate_idr int not null default 7,   -- Rp per coin
  add column if not exists withdraw_min_coins int not null default 1000;

-- ── Tabel permintaan penarikan ──
create table if not exists public.withdrawal_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  coin_amount   int  not null check (coin_amount > 0),
  payout_idr    int  not null check (payout_idr > 0),   -- coin_amount * rate
  rate          int  not null default 7,
  status        text not null default 'pending'
                check (status in ('pending', 'paid', 'rejected')),
  pay_method    text not null check (pay_method in ('bank', 'ewallet', 'qris')),
  pay_account   text not null,        -- nomor rekening / ID e-wallet / QRIS ID
  pay_holder    text not null,        -- nama pemilik rekening
  admin_note    text,
  tx_id         text,                 -- referensi transaksi pembayaran admin
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_withdrawal_user   on public.withdrawal_requests(user_id, created_at desc);
create index if not exists idx_withdrawal_status on public.withdrawal_requests(status, created_at desc);

alter table public.withdrawal_requests enable row level security;

-- User hanya baca milik sendiri; admin lihat semua.
drop policy if exists withdrawal_select_own on public.withdrawal_requests;
create policy withdrawal_select_own on public.withdrawal_requests
  for select using (
    user_id = auth.uid()
    or coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
  );

revoke insert, update, delete on public.withdrawal_requests from anon, authenticated;
grant select on public.withdrawal_requests to anon, authenticated;

-- ============================================================
-- RPC: request_withdrawal(coin, method, account, holder)
-- ============================================================
create or replace function public.request_withdrawal(
  p_coin_amount int, p_pay_method text, p_pay_account text, p_pay_holder text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  points_on boolean; rate int; min_coins int;
  earned int; payout int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled, withdraw_rate_idr, withdraw_min_coins
    into points_on, rate, min_coins from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  -- KYC wajib sudah disetujui
  if not exists (select 1 from kyc_requests k
                 where k.user_id = uid and k.status = 'approved') then
    raise exception 'KYC required';
  end if;

  if p_coin_amount is null or p_coin_amount < min_coins then
    raise exception 'Below minimum'; end if;
  if length(trim(p_pay_account)) < 5 or length(trim(p_pay_holder)) < 3 then
    raise exception 'Invalid payout info'; end if;

  -- hanya earned yang bisa dicairkan
  select coalesce(sum(amount) filter (where bucket='earned'),0)
    into earned from coin_ledger where user_id = uid;
  if earned < p_coin_amount then raise exception 'Not enough withdrawable'; end if;

  payout := p_coin_amount * rate;

  -- debit earned (hold) — jika ditolak admin, direfund
  insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
    values (uid,'earned','withdraw_request',-p_coin_amount,
            p_pay_method, jsonb_build_object('payout_idr',payout));
  perform public.wallet_sync_points(uid);

  insert into withdrawal_requests (user_id, coin_amount, payout_idr, rate, status,
                                   pay_method, pay_account, pay_holder)
  values (uid, p_coin_amount, payout, rate, 'pending',
          p_pay_method, trim(p_pay_account), trim(p_pay_holder));

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'withdraw_request', -p_coin_amount,
            jsonb_build_object('payout_idr',payout));

  return jsonb_build_object('ok', true, 'coin_amount', p_coin_amount,
    'payout_idr', payout, 'status', 'pending', 'rate', rate);
end; $$;
revoke execute on function public.request_withdrawal(int, text, text, text) from public, anon;
grant execute on function public.request_withdrawal(int, text, text, text) to authenticated;

-- ============================================================
-- RPC: get_my_withdrawals()
-- ============================================================
create or replace function public.get_my_withdrawals()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select id, coin_amount, payout_idr, rate, status, pay_method,
           pay_account, pay_holder, admin_note, tx_id, created_at, reviewed_at
    from withdrawal_requests where user_id = auth.uid()
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.get_my_withdrawals() from public, anon;
grant execute on function public.get_my_withdrawals() to authenticated;

-- ============================================================
-- RPC: admin_withdrawal_list(status)
-- ============================================================
create or replace function public.admin_withdrawal_list(p_status text default 'pending')
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select w.id, w.user_id, w.coin_amount, w.payout_idr, w.rate, w.status,
           w.pay_method, w.pay_account, w.pay_holder, w.admin_note, w.tx_id,
           w.created_at, w.reviewed_at, p.nickname, p.email
    from withdrawal_requests w
    join profiles p on p.id = w.user_id
    where (p_status = 'all' or w.status = p_status)
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.admin_withdrawal_list(text) from public, anon;
grant execute on function public.admin_withdrawal_list(text) to authenticated, service_role;

-- ============================================================
-- RPC: admin_withdrawal_review(id, action, note, tx_id)
--   action 'pay'     → status paid + tx_id (pembayaran sudah dikirim)
--   action 'reject'  → refund earned + status rejected + note
-- ============================================================
create or replace function public.admin_withdrawal_review(
  p_request_id uuid, p_action text, p_note text default null, p_tx_id text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); w record;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;

  select * into w from withdrawal_requests where id = p_request_id;
  if not found then raise exception 'Request not found'; end if;
  if w.status <> 'pending' then raise exception 'Already reviewed'; end if;

  if p_action = 'pay' then
    update withdrawal_requests set status = 'paid', tx_id = p_tx_id,
      admin_note = p_note, reviewed_by = uid, reviewed_at = now(), updated_at = now()
      where id = p_request_id;
    insert into public.point_events (user_id, event, amount, metadata)
      values (w.user_id, 'withdraw_paid', -w.coin_amount,
              jsonb_build_object('request', w.id, 'payout_idr', w.payout_idr, 'tx', p_tx_id));
  elsif p_action = 'reject' then
    update withdrawal_requests set status = 'rejected', admin_note = p_note,
      reviewed_by = uid, reviewed_at = now(), updated_at = now()
      where id = p_request_id;
    -- refund earned
    perform public.ledger_credit(w.user_id, 'earned', 'withdraw_refund', w.coin_amount,
      w.id::text, jsonb_build_object('request', w.id));
    perform public.wallet_sync_points(w.user_id);
    insert into public.point_events (user_id, event, amount, metadata)
      values (w.user_id, 'withdraw_refund', w.coin_amount,
              jsonb_build_object('request', w.id));
  else
    raise exception 'Invalid action';
  end if;

  return jsonb_build_object('ok', true, 'status', p_action);
end; $$;
revoke execute on function public.admin_withdrawal_review(uuid, text, text, text) from public, anon;
grant execute on function public.admin_withdrawal_review(uuid, text, text, text) to authenticated, service_role;

-- ============================================================
-- RPC: withdrawal_summary() — konfigurasi rate & min untuk UI
-- ============================================================
create or replace function public.withdrawal_summary()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select jsonb_build_object('rate', withdraw_rate_idr, 'min_coins', withdraw_min_coins)
    into res from app_settings where id = 'global';
  return res;
end; $$;
revoke execute on function public.withdrawal_summary() from public, anon;
grant execute on function public.withdrawal_summary() to authenticated;
