-- ============================================================
-- coin_circulation_report.sql — rekapan peredaran koin & untung/rugi
-- ChatYuk. Semua query READ-ONLY (aman dijalankan kapan saja).
--
-- Cara jalan (Management API — CLI `supabase db query` HANG di Mac):
--   REF=fohcucyyejdryryoxitm
--   TOK="$(security find-generic-password -s 'Supabase CLI' -a 'supabase' -w \
--     | sed 's/^go-keyring-base64://' | base64 -d)"
--   python3 -c "import json;print(json.dumps({'query':open('scripts/coin_circulation_report.sql').read()}))" > /tmp/q.json
--   curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
--     -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
--     --data-binary @/tmp/q.json
--
-- Atau jalankan per bagian: copy satu blok SELECT ke payload yang sama.
-- ============================================================

-- ── 1. PEREDARAN SEKARANG (koin di tangan user) ─────────────────────────
-- "Peredaran koin" = saldo semua user. Beda dengan total yang pernah
-- dikeluarkan (ledger) — koin bisa hangus (cut platform, fee match).
select coalesce(gender,'(null)') as gender,
       count(*) as users,
       sum(points)                        as total_koin,
       sum(bonus_balance)                 as bonus_beredar,
       sum(topup_balance)                 as topup_beredar,
       sum(earned_balance)                as earned_beredar
from profiles
group by 1 order by 1;

-- ── 2. RIWAYAT: dikeluarkan vs dipakai per bucket/type ──────────────────
select bucket, type,
       count(*)                                        as baris,
       sum(amount) filter (where amount > 0)           as dikeluarkan,
       sum(amount) filter (where amount < 0)           as terpakai
from coin_ledger
group by 1,2
order by dikeluarkan desc nulls last;

-- ── 3. BONUS (koin gratis) pernah dikeluarkan ───────────────────────────
select type, count(*) as baris, sum(amount) as koin
from coin_ledger
where bucket = 'bonus' and amount > 0
group by 1 order by 3 desc;

-- ── 4. UANG MASUK (top-up) & UANG KELUAR (withdraw) ─────────────────────
-- Revenue = uang nyata masuk. Withdraw = uang nyata keluar.
select
 (select coalesce(sum(price_idr),0)  from topup_orders where status='paid')      as topup_masuk_idr,
 (select count(*)                     from topup_orders where status='paid')      as topup_order,
 (select coalesce(sum(payout_idr),0)  from withdrawal_requests where status='paid')   as wd_keluar_idr,
 (select coalesce(sum(coin_amount),0) from withdrawal_requests where status='paid')   as wd_koin,
 (select count(*)                     from withdrawal_requests where status='paid')   as wd_count,
 (select coalesce(sum(payout_idr),0)  from withdrawal_requests where status='pending') as wd_pending_idr,
 (select coalesce(sum(coin_amount),0) from withdrawal_requests where status='pending') as wd_pending_koin;

-- ── 5. CUT PLATFORM (koin hangus jadi potongan) ─────────────────────────
select source, count(*) as baris, sum(amount) as koin
from platform_revenue
group by 1 order by 3 desc;

-- ── 6. ARUS 30 HARI TERAKHIR ────────────────────────────────────────────
select bucket, type,
       sum(amount) filter (where amount > 0) as dikeluarkan,
       sum(amount) filter (where amount < 0) as terpakai
from coin_ledger
where created_at > now() - interval '30 days'
group by 1,2 order by 1,2;

-- ── 7. MISI (reward earned female = liabilitas withdraw) ────────────────
select m.mission_key, m.gender, m.reward_coins, m.is_daily,
       (select count(*) from user_missions um where um.mission_id=m.id and um.claimed) as diklaim
from missions m order by m.display_order;

-- ── 8. DETEKTOR BOCOR (harus 0 setelah migrasi 20261101190000) ──────────
-- 8a. Koin BONUS yang dipakai bayar call → 30% nya jadi earned female
--     (withdrawable). Kerugian ≈ koin × 30% × Rp 7.
select coalesce(sum(-amount),0) as bonus_bayar_call
from coin_ledger
where bucket='bonus' and amount < 0 and type in ('call_audio','call_video');

-- 8b. Koin BONUS yang sudah dicairkan via withdraw (harus 0).
select coalesce(sum(-amount),0) as bonus_dicairkan
from coin_ledger
where bucket='bonus' and type='withdraw';

-- 8c. Withdraw yang tidak debit earned (harus 0).
select count(*) as withdraw_non_earned
from coin_ledger
where type='withdraw' and bucket <> 'earned';

-- ── 9. INVARIANT (harus 0 baris) ────────────────────────────────────────
select * from economy_invariant_check(100);

-- ── 10. MODEL UNTUNG/RUGI per 1 koin (dari setting live) ───────────────
-- Rumus:
--   harga_jual_koin   = price_idr / coins            (per paket)
--   masuk_bersih      = harga_jual_koin × (1 − fee Google)   [15% atau 30%]
--   keluar_per_koin   = withdraw_rate_idr × (1 − withdraw_fee_pct/100)
--   pass_through      = bagian koin yang sampai jadi `earned` female
--                       (call 30% · gift 70% · foto 60% · subscribe 70% ·
--                        kirim koin 100%)
--   untung_per_koin   = masuk_bersih − keluar_per_koin × pass_through
--   batas_withdraw    = masuk_bersih / pass_through  (rate Rp yang impas)
with cfg as (
  select call_cut_pct, gift_cut_pct, photo_unlock_owner_pct, subscribe_cut_pct,
         withdraw_rate_idr, withdraw_fee_pct
  from app_settings where id='global'
), pkg as (
  select id, coins, price_idr, price_idr::numeric / coins as jual_per_koin
  from topup_packages where active
), ek as (
  select
    -- skenario pesimis: paket termurah + Google 30%
    min(jual_per_koin) * 0.70 as masuk_bersih_pesimis,
    min(jual_per_koin) * 0.85 as masuk_bersih_optimis,
    (select withdraw_rate_idr from cfg) *
      (1 - (select withdraw_fee_pct from cfg)::numeric / 100) as keluar_per_koin
  from pkg
)
select 'call (cut 70%)'      as jalur, 0.30 as pass_through,
       masuk_bersih_pesimis, keluar_per_koin * 0.30 as keluar_per_koin_dipakai,
       masuk_bersih_pesimis - keluar_per_koin * 0.30 as untung_per_koin,
       masuk_bersih_pesimis / 0.30 as batas_withdraw_rate
from ek
union all
select 'gift (cut 30%)', 0.70, masuk_bersih_pesimis, keluar_per_koin * 0.70,
       masuk_bersih_pesimis - keluar_per_koin * 0.70, masuk_bersih_pesimis / 0.70
from ek
union all
select 'unlock foto (owner 60%)', 0.60, masuk_bersih_pesimis, keluar_per_koin * 0.60,
       masuk_bersih_pesimis - keluar_per_koin * 0.60, masuk_bersih_pesimis / 0.60
from ek
union all
select 'subscribe (cut 30%)', 0.70, masuk_bersih_pesimis, keluar_per_koin * 0.70,
       masuk_bersih_pesimis - keluar_per_koin * 0.70, masuk_bersih_pesimis / 0.70
from ek
union all
select 'kirim koin (100%)', 1.00, masuk_bersih_pesimis, keluar_per_koin,
       masuk_bersih_pesimis - keluar_per_koin, masuk_bersih_pesimis / 1.00
from ek;
