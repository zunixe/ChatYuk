-- menyentuh: _email_is_admin, calls_client_guard, check_user_total_coins,
--            clamp_last_seen, is_room_media_type, streak_bonus_amount
-- Sumber: docs/LINT_FIX_PLAN.md P2 (audit Advisors 2026-11-07).
-- Hardening: pin search_path (anti search-path hijack pada SECURITY DEFINER).
-- Semua body sudah fully-qualified (auth.email(), public.coin_ledger) →
-- SET search_path = '' aman. Tidak ada yang frozen (cek 2026-11-07).
-- Catatan: outbox_mark_local hanya ada di replica (fungsi isolasi) —
-- di-fix terpisah di replica, bukan bagian file ini.

ALTER FUNCTION public._email_is_admin() SET search_path = '';
ALTER FUNCTION public.calls_client_guard() SET search_path = '';
ALTER FUNCTION public.check_user_total_coins(uuid) SET search_path = '';
ALTER FUNCTION public.clamp_last_seen() SET search_path = '';
ALTER FUNCTION public.is_room_media_type(text) SET search_path = '';
ALTER FUNCTION public.streak_bonus_amount(integer) SET search_path = '';
