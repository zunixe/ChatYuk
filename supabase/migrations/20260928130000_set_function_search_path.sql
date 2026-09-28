-- ============================================================
-- Security hardening (audit advisor 2026-09-28) - SET search_path
-- 28 fungsi "function_search_path_mutable" diberi search_path tetap.
--
-- SAFE: hanya `ALTER FUNCTION ... SET search_path` (BUKAN mengganti body
--       definisi, jadi fungsi FROZEN tidak tersentuh). Mencegah search_path
--       hijacking: penyerang tak bisa menaruh objek bernama sama di schema
--       lain lalu memengaruhi resolusi nama di dalam fungsi.
--
-- search_path = public, pg_temp :
--   - `public`      : fungsi/tabel app dipanggil tanpa kualifikasi.
--   - `pg_temp`     : psql convention; pg_temp DULUAN tidak disarankan,
--                     ditaruh belakang supaya tidak menutupi `public`.
--   - TIDAK memasukkan `extensions` (fungsi ini tidak memakai pgcrypto/net;
--     sudah diverifikasi: 0 pemakaian crypt/gen_salt/net.http/geo).
--
-- ROLLBACK: alter function public.<fn>(<args>) reset search_path;
-- ============================================================

alter function public.admin_test(p_chat_id text) set search_path = public, pg_temp;
alter function public.call_history_insert() set search_path = public, pg_temp;
alter function public.check_email_exists(p_email text) set search_path = public, pg_temp;
alter function public.check_private_chat_update() set search_path = public, pg_temp;
alter function public.coin_ledger_no_mutate() set search_path = public, pg_temp;
alter function public.comment_like_count_sync() set search_path = public, pg_temp;
alter function public.comment_share_count_sync() set search_path = public, pg_temp;
alter function public.enforce_age_min() set search_path = public, pg_temp;
alter function public.enforce_storage_photo() set search_path = public, pg_temp;
alter function public.follow_count_sync() set search_path = public, pg_temp;
alter function public.get_data_sizes() set search_path = public, pg_temp;
alter function public.get_last_messages(chat_ids text[]) set search_path = public, pg_temp;
alter function public.get_message_counts(chat_ids text[]) set search_path = public, pg_temp;
alter function public.get_table_sizes() set search_path = public, pg_temp;
alter function public.handle_new_private_message() set search_path = public, pg_temp;
alter function public.increment_unread(chat_id text, receiver_id uuid) set search_path = public, pg_temp;
alter function public.notify_call_ringing() set search_path = public, pg_temp;
alter function public.post_comment_count_sync() set search_path = public, pg_temp;
alter function public.post_like_count_sync() set search_path = public, pg_temp;
alter function public.room_online_counts(p_country text) set search_path = public, pg_temp;
alter function public.set_participant_registered() set search_path = public, pg_temp;
alter function public.set_room_presence_from_profile() set search_path = public, pg_temp;
alter function public.set_sender_name_from_profile() set search_path = public, pg_temp;
alter function public.streak_bonus_amount(streak integer) set search_path = public, pg_temp;
alter function public.subscriber_count_sync() set search_path = public, pg_temp;
alter function public.trg_coin_ledger_balance() set search_path = public, pg_temp;
alter function public.week_label(tz_offset_minutes integer) set search_path = public, pg_temp;
alter function public.week_start_utc(tz_offset_minutes integer) set search_path = public, pg_temp;
