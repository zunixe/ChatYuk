-- ============================================================
-- ChatYuk — Topup Google Play Billing (DB)
--
-- Konteks keputusan produk: satu-satunya jalur topup coin = Google Play
-- Billing (Midtrans/iPaymu ditinggalkan, lihat docs/restore-financial-features.md).
-- Karena Play Billing: coin TIDAK bisa dicairkan (tanpa cash-out) → Play-safe.
--
-- Alur:
--   1. Client query produk Play (product_id) → tampilkan paket (topup_packages).
--   2. User beli via Play Billing → client dapat purchase_token.
--   3. Client kirim token ke Edge Function `play-topup-verify` →
--      server verifikasi ke Google Play Developer API → panggil RPC
--      credit_play_topup (idempoten by purchase_token).
--   4. Coin masuk saldo user.
--
-- Tambahan pada topup_packages: kolom play_product_id (produk Play).
-- RPC baru: credit_play_topup (service_role).
--
-- Tabel topup_packages/topup_orders SUDAH ADA (20260814240000). Kita pakai
-- ulang & tambah kolom. Idempotent.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Kolom Play di katalog paket
-- ──────────────────────────────────────────────
alter table public.topup_packages
  add column if not exists play_product_id text;

-- Isi play_product_id berdasar id paket (konvensi: chatyuk_coins_<coins>).
-- (Admin bisa ubah lewat panel/dashboard sesuai produk yang dibuat di Play.)
update public.topup_packages
  set play_product_id = 'chatyuk_coins_' || coins::text
  where play_product_id is null;

-- ──────────────────────────────────────────────
-- 2. Kolom Play di orders
-- ──────────────────────────────────────────────
alter table public.topup_orders
  add column if not exists purchase_token text,
  add column if not exists play_order_id  text,   -- Google orderId
  add column if not exists platform       text not null default 'play';

-- Cegah double-credit token Play (unique sekali pakai).
create unique index if not exists uq_topup_orders_purchase_token
  on public.topup_orders(purchase_token)
  where purchase_token is not null;

-- ──────────────────────────────────────────────
-- 3. RPC: credit_play_topup — dipanggil edge function (service_role)
--    setelah verifikasi purchase_token ke Google. Idempoten:
--    - bila purchase_token sudah pernah di-credit → tidak dobel.
--    Coin masuk bucket 'topup' (uang asli). wallet_sync_points sinkron.
-- ──────────────────────────────────────────────
create or replace function public.credit_play_topup(
  p_user uuid,
  p_play_product_id text,
  p_purchase_token text,
  p_play_order_id text default null,
  p_raw jsonb default '{}'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  pk record; me_order text; tot int; existing record;
begin
  if p_user is null then raise exception 'Missing user'; end if;
  if p_purchase_token is null or length(p_purchase_token) < 4 then
    raise exception 'Invalid purchase token';
  end if;

  -- Idempotensi: token sudah pernah di-credit?
  select * into existing from topup_orders where purchase_token = p_purchase_token;
  if found then
    return jsonb_build_object('ok', true, 'already', true,
      'coins', existing.coins, 'total', public.yukcoin_total(p_user));
  end if;

  -- Cari paket berdasarkan produk Play.
  select * into pk from topup_packages
    where play_product_id = p_play_product_id and active = true;
  if not found then raise exception 'Unknown Play product: %', p_play_product_id; end if;

  me_order := 'play_' || replace(gen_random_uuid()::text, '-', '');

  insert into topup_orders (id, user_id, package_id, coins, price_idr, status,
                            provider, provider_ref, purchase_token, play_order_id,
                            platform, raw, paid_at)
    values (me_order, p_user, pk.id, pk.coins, pk.price_idr, 'paid',
            'play_billing', p_play_order_id, p_purchase_token, p_play_order_id,
            'play', coalesce(p_raw, '{}'::jsonb), now());

  -- Coin masuk bucket 'topup' (lineage uang asli).
  tot := public.ledger_credit(p_user, 'topup', 'topup', pk.coins,
           me_order, jsonb_build_object('play_product', p_play_product_id,
           'price_idr', pk.price_idr));

  return jsonb_build_object('ok', true, 'already', false, 'coins', pk.coins,
    'total', tot, 'order_id', me_order);
end; $$;
revoke execute on function public.credit_play_topup(uuid, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.credit_play_topup(uuid, text, text, text, jsonb) to service_role;

-- ──────────────────────────────────────────────
-- 4. RPC: list_topup_packages — sertakan play_product_id (untuk client)
--    (re-enable execute yang di-revoke 20260819140000).
-- ──────────────────────────────────────────────
create or replace function public.list_topup_packages()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.sort_order), '[]'::jsonb) into res
  from (
    select id, coins, price_idr, bonus_label, sort_order, play_product_id
    from topup_packages where active = true
  ) x;
  return res;
end; $$;
grant execute on function public.list_topup_packages() to anon, authenticated, service_role;

-- ──────────────────────────────────────────────
-- 5. Katalog paket (harga Play-accurate, margin aman setelah fee Google).
--    Rasio membaik untuk paket besar. price_idr > nilai coin (margin depan).
-- ──────────────────────────────────────────────
insert into public.topup_packages (id, coins, price_idr, bonus_label, sort_order, play_product_id, active) values
  ('pkg_10k',   700,   10000,  null,   1, 'chatyuk_coins_700',   true),
  ('pkg_25k',   1850,  25000,  '+5%',  2, 'chatyuk_coins_1850',  true),
  ('pkg_50k',   3900,  50000,  '+10%', 3, 'chatyuk_coins_3900',  true),
  ('pkg_100k',  8200,  100000, '+13%', 4, 'chatyuk_coins_8200',  true),
  ('pkg_250k',  21500, 250000, '+15%', 5, 'chatyuk_coins_21500', true)
on conflict (id) do update set
  coins = excluded.coins,
  price_idr = excluded.price_idr,
  bonus_label = excluded.bonus_label,
  sort_order = excluded.sort_order,
  play_product_id = excluded.play_product_id,
  active = true;
