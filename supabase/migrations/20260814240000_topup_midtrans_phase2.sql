-- ============================================================
-- ChatYuk Wallet FASE 2 — Deposit (Top-Up) via Midtrans Snap
--
-- Alur:
--   1. Client panggil Edge Function `topup-create` → buat baris topup_orders
--      (status 'pending') + minta Snap token ke Midtrans.
--   2. User bayar (QRIS/VA/e-wallet) di Snap.
--   3. Midtrans kirim webhook → Edge Function `topup-webhook` verifikasi
--      signature → panggil RPC `credit_topup_order` → coin masuk bucket 'topup'.
--   4. RPC idempoten: order yang sudah 'paid' tidak akan double-credit.
--
-- Harga (rupiah) SENGAJA lebih besar dari jumlah coin → itu margin depan.
-- Makin besar paket, rasio makin bagus untuk user (insentif beli banyak),
-- tapi tetap price_idr > coins.
-- ============================================================

-- ── Katalog paket top-up ──
create table if not exists public.topup_packages (
  id          text primary key,
  coins       int  not null check (coins > 0),
  price_idr   int  not null check (price_idr > 0),
  bonus_label text,             -- mis. '+10%'
  sort_order  int  not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Seed paket (price_idr > coins). Rasio membaik untuk paket besar.
insert into public.topup_packages (id, coins, price_idr, bonus_label, sort_order) values
  ('pkg_10k',   800,   10000,  null,   1),   -- 12.5 rupiah/coin
  ('pkg_25k',   2100,  25000,  '+5%',  2),   -- ~11.9
  ('pkg_50k',   4400,  50000,  '+10%', 3),   -- ~11.4
  ('pkg_100k',  9000,  100000, '+13%', 4),   -- ~11.1
  ('pkg_250k',  23000, 250000, '+15%', 5)    -- ~10.9
on conflict (id) do update set
  coins = excluded.coins,
  price_idr = excluded.price_idr,
  bonus_label = excluded.bonus_label,
  sort_order = excluded.sort_order,
  active = true;

alter table public.topup_packages enable row level security;
drop policy if exists topup_packages_select on public.topup_packages;
create policy topup_packages_select on public.topup_packages
  for select using (active = true);
grant select on public.topup_packages to anon, authenticated;

-- ── Order top-up ──
create table if not exists public.topup_orders (
  id           text primary key,               -- order_id unik (dikirim ke Midtrans)
  user_id      uuid not null references auth.users(id) on delete cascade,
  package_id   text references public.topup_packages(id),
  coins        int  not null,
  price_idr    int  not null,
  status       text not null default 'pending'
                 check (status in ('pending','paid','failed','expired','cancelled')),
  provider     text not null default 'midtrans',
  provider_ref text,                            -- transaction_id dari Midtrans
  snap_token   text,
  raw          jsonb not null default '{}',
  created_at   timestamptz not null default now(),
  paid_at      timestamptz
);
create index if not exists idx_topup_orders_user on public.topup_orders(user_id, created_at);
create index if not exists idx_topup_orders_status on public.topup_orders(status);

alter table public.topup_orders enable row level security;
-- User boleh lihat order sendiri (admin bypass). Tidak boleh insert/update
-- langsung — hanya via Edge Function (service_role) / RPC security definer.
drop policy if exists topup_orders_select_own on public.topup_orders;
create policy topup_orders_select_own on public.topup_orders
  for select using (
    auth.uid() = user_id
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );
revoke insert, update, delete on public.topup_orders from anon, authenticated;
grant select on public.topup_orders to authenticated;

-- ============================================================
-- RPC: list_topup_packages() — paket aktif, urut
-- ============================================================
create or replace function public.list_topup_packages()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.sort_order), '[]'::jsonb) into res
  from (
    select id, coins, price_idr, bonus_label, sort_order
    from topup_packages where active = true
  ) x;
  return res;
end; $$;
grant execute on function public.list_topup_packages() to anon, authenticated, service_role;

-- ============================================================
-- RPC: create_topup_order — dipanggil Edge Function (service_role).
-- Membuat baris order 'pending'. Validasi paket & harga dari server
-- (client TIDAK boleh tentukan coins/price sendiri).
-- ============================================================
create or replace function public.create_topup_order(
  p_order_id text, p_user uuid, p_package_id text, p_snap_token text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk record;
begin
  select * into pk from topup_packages where id = p_package_id and active = true;
  if not found then raise exception 'Invalid package'; end if;

  insert into topup_orders (id, user_id, package_id, coins, price_idr, status, snap_token)
    values (p_order_id, p_user, pk.id, pk.coins, pk.price_idr, 'pending', p_snap_token);

  return jsonb_build_object('order_id', p_order_id, 'coins', pk.coins,
    'price_idr', pk.price_idr);
end; $$;
revoke execute on function public.create_topup_order(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.create_topup_order(text, uuid, text, text) to service_role;

-- ============================================================
-- RPC: credit_topup_order — dipanggil webhook (service_role) SETELAH
-- verifikasi signature Midtrans. Idempoten: hanya credit sekali.
-- Coin masuk bucket 'topup'.
-- ============================================================
create or replace function public.credit_topup_order(
  p_order_id text, p_status text, p_provider_ref text default null, p_raw jsonb default '{}'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare o record; tot int;
begin
  select * into o from topup_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found: %', p_order_id; end if;

  -- Sudah paid → idempoten, jangan double-credit
  if o.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'coins', o.coins);
  end if;

  if p_status = 'paid' then
    update topup_orders set status = 'paid', provider_ref = p_provider_ref,
      raw = coalesce(p_raw,'{}'::jsonb), paid_at = now()
      where id = p_order_id;

    tot := public.ledger_credit(o.user_id, 'topup', 'topup', o.coins,
      p_order_id, jsonb_build_object('order_id', p_order_id, 'price_idr', o.price_idr));

    return jsonb_build_object('ok', true, 'credited', o.coins, 'total', tot);
  else
    update topup_orders set status = p_status, provider_ref = p_provider_ref,
      raw = coalesce(p_raw,'{}'::jsonb)
      where id = p_order_id;
    return jsonb_build_object('ok', true, 'status', p_status);
  end if;
end; $$;
revoke execute on function public.credit_topup_order(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.credit_topup_order(text, text, text, jsonb) to service_role;

-- ============================================================
-- RPC: get_my_topup_orders — riwayat order user (untuk UI status)
-- ============================================================
create or replace function public.get_my_topup_orders(row_limit int default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select id, package_id, coins, price_idr, status, created_at, paid_at
    from topup_orders where user_id = auth.uid()
    order by created_at desc limit greatest(1, least(row_limit, 100))
  ) x;
  return res;
end; $$;
revoke execute on function public.get_my_topup_orders(int) from public, anon;
grant execute on function public.get_my_topup_orders(int) to authenticated, service_role;
