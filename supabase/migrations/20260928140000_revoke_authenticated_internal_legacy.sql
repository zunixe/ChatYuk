-- ============================================================
-- Security hardening lanjutan (audit advisor 2026-09-28) - REVOKE EXECUTE
-- 37 fungsi internal/trigger/cron LEGACY dari PUBLIC, anon, authenticated.
--
-- SAFE: hanya mencabut EXECUTE (BUKAN mengganti definisi fungsi, jadi fungsi
--       FROZEN tidak tersentuh body-nya). 37 fungsi ini TERVERIFIKASI tidak
--       dipanggil klien (0 referensi di lib/ sebagai .rpc/measuredRpc, dan
--       tidak ada di daftar RPC `admin_service.dart`); dipakai trigger/cron/
--       rantai internal saja.
--
-- Aman untuk pemanggilan internal: SEMUA pemanggil internal fungsi ini adalah
--   SECURITY DEFINER (diverifikasi: ledger_spend_dual dipanggil boost_post/
--   send_gift/unlock_photo/create_private_room/extend_private_room — semua
--   definer; ledger_spend_paid oleh send_coins/subscribe_creator/ledger_spend_dual;
--   yukcoin_total oleh spend_yukcoin). Definer jalan sebagai OWNER (postgres)
--   sehingga tetap punya EXECUTE -> rantai TIDAK putus.
--
-- Helper lintas-fungsi/policy SENGAJA DIBIARKAN (dipakai definer/policy lain):
--   _anon_gate_insert, _anon_write_ok, _privacy_are_friends,
--   _social_registered_guard, is_admin_request, chat_photos_guard,
--   storage_object_owner_ok, user_fcm_tokens, privacy_can_view, privacy_friends.
--
-- PENTING: WAJIB `from public` (anon/authenticated mewarisi EXECUTE PUBLIC).
--
-- ROLLBACK: grant execute on function public.<fn>(<args>) to public;
-- ============================================================

revoke execute on function public.admin_dummy_uids() from public, anon, authenticated;
revoke execute on function public.admin_excluded_uids() from public, anon, authenticated;
revoke execute on function public.admin_get_ai_reply_log(p_chat_id text, p_limit integer) from public, anon, authenticated;
revoke execute on function public.admin_get_excluded_uids() from public, anon, authenticated;
revoke execute on function public.admin_get_location_history(p_uid uuid, p_limit integer) from public, anon, authenticated;
revoke execute on function public.admin_list_dummies() from public, anon, authenticated;
revoke execute on function public.admin_location_sources() from public, anon, authenticated;
revoke execute on function public.admin_register_dummy(p_uid uuid, p_nickname text, p_refresh_token text, p_gender text, p_age integer, p_country text, p_city text) from public, anon, authenticated;
revoke execute on function public.admin_renew_dummy_token(p_uid uuid) from public, anon, authenticated;
revoke execute on function public.admin_set_excluded_uids(p_list jsonb) from public, anon, authenticated;
revoke execute on function public.admin_stats_compute() from public, anon, authenticated;
revoke execute on function public.ai_log_reply(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean, p_stage text, p_decision text, p_detail jsonb) from public, anon, authenticated;
revoke execute on function public.ai_memory_cleanup() from public, anon, authenticated;
revoke execute on function public.ai_presence_tick() from public, anon, authenticated;
revoke execute on function public.ai_proactive_tick() from public, anon, authenticated;
revoke execute on function public.ai_reply_claim(p_msg_id bigint, p_dummy uuid) from public, anon, authenticated;
revoke execute on function public.ai_reply_claim_recovery() from public, anon, authenticated;
revoke execute on function public.ai_reply_missed_recovery() from public, anon, authenticated;
revoke execute on function public.ai_story_cleanup() from public, anon, authenticated;
revoke execute on function public.award_share_click(p_sharer uuid, p_ip text) from public, anon, authenticated;
revoke execute on function public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text) from public, anon, authenticated;
revoke execute on function public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text, p_avatar text) from public, anon, authenticated;
revoke execute on function public.friend_request_inbox() from public, anon, authenticated;
revoke execute on function public.friend_request_outbox() from public, anon, authenticated;
revoke execute on function public.get_ledger_history(row_limit integer) from public, anon, authenticated;
revoke execute on function public.ledger_credit(p_user uuid, p_bucket text, p_type text, p_amount integer, p_ref text, p_meta jsonb) from public, anon, authenticated;
revoke execute on function public.ledger_spend(p_user uuid, p_type text, p_amount integer, p_ref text) from public, anon, authenticated;
revoke execute on function public.ledger_spend_dual(p_user uuid, p_type text, p_paid integer, p_bonus integer, p_ref text) from public, anon, authenticated;
revoke execute on function public.ledger_spend_paid(p_user uuid, p_type text, p_amount integer, p_ref text) from public, anon, authenticated;
revoke execute on function public.mark_chats_user_deleted(p_uid uuid) from public, anon, authenticated;
revoke execute on function public.my_share_stats() from public, anon, authenticated;
revoke execute on function public.presence_idle_tick(p_idle_after interval) from public, anon, authenticated;
revoke execute on function public.purge_inactive_accounts() from public, anon, authenticated;
revoke execute on function public.recount_social_counts() from public, anon, authenticated;
revoke execute on function public.room_voice_sweep() from public, anon, authenticated;
revoke execute on function public.send_reengage_notifications(p_batch integer) from public, anon, authenticated;
revoke execute on function public.social_push(p_to uuid, p_title text, p_body text, p_data jsonb) from public, anon, authenticated;
revoke execute on function public.yukcoin_total(p_user uuid) from public, anon, authenticated;

-- service_role tetap boleh (dipakai cron/edge/admin panel backend).
grant execute on function public.admin_register_dummy(p_uid uuid, p_nickname text, p_refresh_token text, p_gender text, p_age integer, p_country text, p_city text) to service_role;
grant execute on function public.admin_renew_dummy_token(p_uid uuid) to service_role;
grant execute on function public.admin_dummy_uids() to service_role;
grant execute on function public.admin_stats_compute() to service_role;
grant execute on function public.ai_presence_tick() to service_role;
grant execute on function public.ai_proactive_tick() to service_role;
grant execute on function public.ai_reply_claim(p_msg_id bigint, p_dummy uuid) to service_role;
grant execute on function public.ai_reply_claim_recovery() to service_role;
grant execute on function public.ai_reply_missed_recovery() to service_role;
grant execute on function public.ai_memory_cleanup() to service_role;
grant execute on function public.ai_story_cleanup() to service_role;
grant execute on function public.ai_log_reply(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean, p_stage text, p_decision text, p_detail jsonb) to service_role;
grant execute on function public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text) to service_role;
grant execute on function public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text, p_avatar text) to service_role;
grant execute on function public.get_ledger_history(row_limit integer) to service_role;
grant execute on function public.ledger_credit(p_user uuid, p_bucket text, p_type text, p_amount integer, p_ref text, p_meta jsonb) to service_role;
grant execute on function public.ledger_spend(p_user uuid, p_type text, p_amount integer, p_ref text) to service_role;
grant execute on function public.ledger_spend_dual(p_user uuid, p_type text, p_paid integer, p_bonus integer, p_ref text) to service_role;
grant execute on function public.ledger_spend_paid(p_user uuid, p_type text, p_amount integer, p_ref text) to service_role;
grant execute on function public.mark_chats_user_deleted(p_uid uuid) to service_role;
grant execute on function public.my_share_stats() to service_role;
grant execute on function public.award_share_click(p_sharer uuid, p_ip text) to service_role;
grant execute on function public.presence_idle_tick(p_idle_after interval) to service_role;
grant execute on function public.purge_inactive_accounts() to service_role;
grant execute on function public.recount_social_counts() to service_role;
grant execute on function public.room_voice_sweep() to service_role;
grant execute on function public.send_reengage_notifications(p_batch integer) to service_role;
grant execute on function public.social_push(p_to uuid, p_title text, p_body text, p_data jsonb) to service_role;
grant execute on function public.yukcoin_total(p_user uuid) to service_role;
grant execute on function public.friend_request_inbox() to service_role;
grant execute on function public.friend_request_outbox() to service_role;
grant execute on function public.admin_get_ai_reply_log(p_chat_id text, p_limit integer) to service_role;
grant execute on function public.admin_get_excluded_uids() to service_role;
grant execute on function public.admin_set_excluded_uids(p_list jsonb) to service_role;
grant execute on function public.admin_get_location_history(p_uid uuid, p_limit integer) to service_role;
grant execute on function public.admin_list_dummies() to service_role;
grant execute on function public.admin_location_sources() to service_role;
grant execute on function public.admin_excluded_uids() to service_role;
