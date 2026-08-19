-- ─────────────────────────────────────────────────────────────────────────────
-- Nonaktifkan fitur finansial (top-up, KYC, withdraw, revenue) — reversible.
--
-- Konteks: fitur finansial dihapus total dari aplikasi (kedua flavor) supaya
-- Play-safe. Tabel & fungsi TIDAK di-drop — hanya REVOKE EXECUTE sehingga
-- siapa pun (anon/authenticated) yang mencoba memanggil dapat error
-- "permission denied". Untuk mengaktifkan kembali, jalankan ulang migrasi
-- finansial terkait (create or replace = mengembalikan grant secara default).
--
-- Lihat: docs/restore-financial-features.md
-- ─────────────────────────────────────────────────────────────────────────────

-- Top-Up (Midtrans/iPaymu)
revoke execute on function public.list_topup_packages() from anon, authenticated;
revoke execute on function public.create_topup_order(text, uuid, text, text) from anon, authenticated;
revoke execute on function public.credit_topup_order(text, text, text, jsonb) from anon, authenticated;
revoke execute on function public.get_my_topup_orders(integer) from anon, authenticated;
revoke execute on function public.ledger_spend_topup(uuid, text, integer, text) from anon, authenticated;

-- KYC
revoke execute on function public.submit_kyc(text, text, text, text, text, date) from anon, authenticated;
revoke execute on function public.get_my_kyc() from anon, authenticated;
revoke execute on function public.admin_kyc_list(text) from anon, authenticated;
revoke execute on function public.admin_kyc_review(uuid, boolean, text) from anon, authenticated;

-- Withdraw (pencairan)
revoke execute on function public.request_withdrawal(integer, text, text, text) from anon, authenticated;
revoke execute on function public.get_my_withdrawals() from anon, authenticated;
revoke execute on function public.admin_withdrawal_list(text) from anon, authenticated;
revoke execute on function public.admin_withdrawal_review(uuid, text, text, text) from anon, authenticated;
revoke execute on function public.withdrawal_summary() from anon, authenticated;

-- Revenue (admin)
revoke execute on function public.admin_gift_revenue() from anon, authenticated;
revoke execute on function public.admin_revenue_overview() from anon, authenticated;
