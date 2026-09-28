-- ============================================================
-- Security hardening (audit advisor 2026-09-28) - REVOKE EXECUTE
-- fungsi internal/trigger/admin dari PUBLIC, anon, authenticated.
--
-- SAFE: hanya mencabut EXECUTE (BUKAN mengganti definisi fungsi, jadi
--       fungsi FROZEN tidak tersentuh body-nya). 56 fungsi ini
--       TERVERIFIKASI tidak dipanggil klien (0 referensi di lib/ sebagai
--       .rpc('x') / measuredRpc(_sb,'x')); sisanya dipakai trigger/cron/
--       admin. Helper lintas-fungsi & policy (is_admin_request, fn_room_role,
--       _privacy_are_friends, _social_registered_guard, _anon_gate_insert,
--       storage_object_owner_ok, chat_photos_guard) SENGAJA DIBIARKAN.
--
-- PENTING - kenapa `from public`: Postgres memberi EXECUTE ke PUBLIC secara
-- default. `revoke ... from anon` SENDIRIAN tidak cukup karena anon tetap
-- mewarisi EXECUTE dari PUBLIC (inilah kenapa advisor menandai semua fungsi).
-- Jadi WAJIB `from public` juga.
--
-- Aman untuk pemanggilan internal: fungsi SECURITY DEFINER jalan sebagai
-- OWNER (postgres) sehingga tetap punya EXECUTE. Trigger juga jalan sebagai
-- owner tabel. HANYA akses langsung client (anon/authenticated) yang ditutup.
--
-- ROLLBACK: grant execute on function public.<fn>(<args>) to public;
-- ============================================================

revoke execute on function public.admin_contact_delete(p_id uuid) from public, anon, authenticated;
revoke execute on function public.admin_contact_messages_page(p_limit integer, p_offset integer) from public, anon, authenticated;
revoke execute on function public.admin_contact_set_read(p_id uuid, p_read boolean) from public, anon, authenticated;
revoke execute on function public.admin_registrations_daily(p_year integer, p_month integer) from public, anon, authenticated;
revoke execute on function public.admin_set_privacy_bypass(p_enabled boolean) from public, anon, authenticated;
revoke execute on function public.admin_storage_stats() from public, anon, authenticated;
revoke execute on function public.admin_sweep_calls() from public, anon, authenticated;
revoke execute on function public.ai_reply_enqueue() from public, anon, authenticated;
revoke execute on function public.ai_reply_post(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean) from public, anon, authenticated;
revoke execute on function public.call_history_insert() from public, anon, authenticated;
revoke execute on function public.check_private_chat_update() from public, anon, authenticated;
revoke execute on function public.comment_like_count_sync() from public, anon, authenticated;
revoke execute on function public.comment_share_count_sync() from public, anon, authenticated;
revoke execute on function public.dummy_heartbeat() from public, anon, authenticated;
revoke execute on function public.dummy_uids() from public, anon, authenticated;
revoke execute on function public.enforce_invisible() from public, anon, authenticated;
revoke execute on function public.fix_story_visibility() from public, anon, authenticated;
revoke execute on function public.fn_archive_deleted_user(p_uid uuid, p_reason text, p_claimed_by uuid, p_claimed_nick text) from public, anon, authenticated;
revoke execute on function public.follow_count_sync() from public, anon, authenticated;
revoke execute on function public.get_chat_messages(p_chat_id text, p_before_id bigint, p_limit integer) from public, anon, authenticated;
revoke execute on function public.get_data_sizes() from public, anon, authenticated;
revoke execute on function public.get_room_messages(p_room_id text, p_before_id bigint, p_limit integer) from public, anon, authenticated;
revoke execute on function public.get_share_url() from public, anon, authenticated;
revoke execute on function public.get_table_sizes() from public, anon, authenticated;
revoke execute on function public.handle_new_private_message() from public, anon, authenticated;
revoke execute on function public.increment_unread(chat_id text, receiver_id uuid) from public, anon, authenticated;
revoke execute on function public.ledger_spend_topup(p_user uuid, p_type text, p_amount integer, p_ref text) from public, anon, authenticated;
revoke execute on function public.list_topup_packages() from public, anon, authenticated;
revoke execute on function public.notify_broadcast_started() from public, anon, authenticated;
revoke execute on function public.notify_call_ended() from public, anon, authenticated;
revoke execute on function public.notify_call_ringing() from public, anon, authenticated;
revoke execute on function public.notify_contact_online() from public, anon, authenticated;
revoke execute on function public.notify_mention_room() from public, anon, authenticated;
revoke execute on function public.notify_online_fanout() from public, anon, authenticated;
revoke execute on function public.notify_post_followers() from public, anon, authenticated;
revoke execute on function public.notify_private_message() from public, anon, authenticated;
revoke execute on function public.notify_room_fanout() from public, anon, authenticated;
revoke execute on function public.notify_timeline_count_fanout() from public, anon, authenticated;
revoke execute on function public.notify_timeline_post_fanout() from public, anon, authenticated;
revoke execute on function public.post_comment_count_sync() from public, anon, authenticated;
revoke execute on function public.post_like_count_sync() from public, anon, authenticated;
revoke execute on function public.posts_fill_country() from public, anon, authenticated;
revoke execute on function public.profiles_ledger_signup() from public, anon, authenticated;
revoke execute on function public.purge_expired_stories() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
revoke execute on function public.scrub_reply_snapshot_private() from public, anon, authenticated;
revoke execute on function public.scrub_reply_snapshot_room() from public, anon, authenticated;
revoke execute on function public.set_participant_registered() from public, anon, authenticated;
revoke execute on function public.set_room_presence_from_profile() from public, anon, authenticated;
revoke execute on function public.set_sender_name_from_profile() from public, anon, authenticated;
revoke execute on function public.subscriber_count_sync() from public, anon, authenticated;
revoke execute on function public.sync_dummy_nickname() from public, anon, authenticated;
revoke execute on function public.sync_profile_names() from public, anon, authenticated;
revoke execute on function public.sync_profile_to_chats() from public, anon, authenticated;
revoke execute on function public.trg_ban_nickname() from public, anon, authenticated;
revoke execute on function public.wallet_sync_points(p_user uuid) from public, anon, authenticated;

-- service_role & postgres tetap boleh EXECUTE (dipakai admin panel/edge/cron).
-- (service_role default sudah punya; ini eksplisit untuk kejelasan.)
grant execute on function public.admin_contact_delete(p_id uuid) to service_role;
grant execute on function public.admin_contact_messages_page(p_limit integer, p_offset integer) to service_role;
grant execute on function public.admin_contact_set_read(p_id uuid, p_read boolean) to service_role;
grant execute on function public.admin_registrations_daily(p_year integer, p_month integer) to service_role;
grant execute on function public.admin_set_privacy_bypass(p_enabled boolean) to service_role;
grant execute on function public.admin_storage_stats() to service_role;
grant execute on function public.admin_sweep_calls() to service_role;
grant execute on function public.ai_reply_enqueue() to service_role;
grant execute on function public.ai_reply_post(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean) to service_role;
grant execute on function public.call_history_insert() to service_role;
grant execute on function public.get_chat_messages(p_chat_id text, p_before_id bigint, p_limit integer) to service_role;
grant execute on function public.get_data_sizes() to service_role;
grant execute on function public.get_room_messages(p_room_id text, p_before_id bigint, p_limit integer) to service_role;
grant execute on function public.get_share_url() to service_role;
grant execute on function public.get_table_sizes() to service_role;
grant execute on function public.dummy_heartbeat() to service_role;
grant execute on function public.dummy_uids() to service_role;
grant execute on function public.fn_archive_deleted_user(p_uid uuid, p_reason text, p_claimed_by uuid, p_claimed_nick text) to service_role;
grant execute on function public.ledger_spend_topup(p_user uuid, p_type text, p_amount integer, p_ref text) to service_role;
grant execute on function public.list_topup_packages() to service_role;
grant execute on function public.posts_fill_country() to service_role;
grant execute on function public.purge_expired_stories() to service_role;
grant execute on function public.fix_story_visibility() to service_role;
grant execute on function public.scrub_reply_snapshot_private() to service_role;
grant execute on function public.scrub_reply_snapshot_room() to service_role;
grant execute on function public.wallet_sync_points(p_user uuid) to service_role;
grant execute on function public.increment_unread(chat_id text, receiver_id uuid) to service_role;
