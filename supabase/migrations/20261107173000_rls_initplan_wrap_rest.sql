-- menyentuh: (RLS policy saja, tidak menyentuh fungsi)
-- Lanjutan 20261107170000: wrap SISA policy dgn auth.uid()/auth.jwt() langsung
-- (audit kanonik NULL-safe: 88 policy di 53 tabel, prod = replica).
-- Semantik policy TIDAK berubah — hanya pola evaluasi initplan.
-- Uji: replica 43 dulu, lalu production via Management API.

ALTER POLICY app_settings_admin_insert ON public.app_settings -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: app_settings
  WITH CHECK ((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text));
ALTER POLICY app_settings_admin_update ON public.app_settings -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: app_settings
  USING ((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text));
ALTER POLICY blocks_delete_own ON public.blocks -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: blocks
  USING (((select auth.uid()) = blocker_id));
ALTER POLICY blocks_insert_own ON public.blocks -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: blocks
  WITH CHECK ((((select auth.uid()) = blocker_id) AND (blocker_id <> blocked_id)));
ALTER POLICY blocks_select_own ON public.blocks -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: blocks
  USING (((select auth.uid()) = blocker_id));
ALTER POLICY bonus_claims_select_own ON public.bonus_claims -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: bonus_claims
  USING (((user_id = (select auth.uid())) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY call_signals_insert ON public.call_signals -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: call_signals
  WITH CHECK (((from_uid = (select auth.uid())) AND ((EXISTS ( SELECT 1
   FROM calls c
  WHERE ((c.id = call_signals.call_id) AND ((c.caller_id = (select auth.uid())) OR (c.callee_id = (select auth.uid())))))) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text))));
ALTER POLICY call_signals_select ON public.call_signals -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: call_signals
  USING (((EXISTS ( SELECT 1
   FROM calls c
  WHERE ((c.id = call_signals.call_id) AND ((c.caller_id = (select auth.uid())) OR (c.callee_id = (select auth.uid())))))) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY calls_insert ON public.calls -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: calls
  WITH CHECK ((((select auth.uid()) = caller_id) AND privacy_can_view(callee_id, 'call'::text, (select auth.uid())) AND ((COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text) OR (COALESCE(( SELECT profiles.is_registered
   FROM profiles
  WHERE (profiles.id = (select auth.uid()))), false) AND (NOT (EXISTS ( SELECT 1
   FROM admin_dummy_uids() du(du)
  WHERE (du.du = (select auth.uid())))))) OR (COALESCE(( SELECT app_settings.call_anon_enabled
   FROM app_settings
  WHERE (app_settings.id = 'global'::text)), false) AND (((select auth.uid()) IN ( SELECT du.du
   FROM admin_dummy_uids() du(du))) OR (COALESCE(( SELECT profiles.is_registered
   FROM profiles
  WHERE (profiles.id = (select auth.uid()))), false) = false))))));
ALTER POLICY calls_select ON public.calls -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: calls
  USING ((((select auth.uid()) = caller_id) OR ((select auth.uid()) = callee_id)));
ALTER POLICY calls_select_admin ON public.calls -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: calls
  USING ((COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text));
ALTER POLICY chat_poll_votes_select_participant ON public.chat_poll_votes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: chat_poll_votes
  USING ((EXISTS ( SELECT 1
   FROM private_chats pc
  WHERE ((pc.chat_id = chat_poll_votes.chat_id) AND ((select auth.uid()) = ANY (pc.participants))))));
ALTER POLICY coin_ledger_select_own ON public.coin_ledger -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: coin_ledger
  USING ((((select auth.uid()) = user_id) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY comment_likes_delete_own ON public.comment_likes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: comment_likes
  USING (((select auth.uid()) = user_id));
ALTER POLICY comment_likes_insert_own ON public.comment_likes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: comment_likes
  WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY comment_shares_delete_own ON public.comment_shares -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: comment_shares
  USING (((select auth.uid()) = user_id));
ALTER POLICY comment_shares_insert_own ON public.comment_shares -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: comment_shares
  WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY country_moderators_select ON public.country_moderators -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: country_moderators
  USING (((uid = (select auth.uid())) OR is_chatyuk_admin((select auth.uid()))));
ALTER POLICY country_send_permits_select ON public.country_send_permits -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: country_send_permits
  USING (((uid = (select auth.uid())) OR is_chatyuk_admin((select auth.uid())) OR is_country_moderator(country, (select auth.uid()))));
ALTER POLICY follows_delete_own ON public.follows -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: follows
  USING (((select auth.uid()) = follower_id));
ALTER POLICY follows_insert_own ON public.follows -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: follows
  WITH CHECK ((((select auth.uid()) = follower_id) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = follows.follower_id) AND (p.is_registered = true)))) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = follows.followee_id) AND (p.is_registered = true))))));
ALTER POLICY friend_requests_insert_own ON public.friend_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: friend_requests
  WITH CHECK ((((select auth.uid()) = from_id) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = friend_requests.from_id) AND (p.is_registered = true)))) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = friend_requests.to_id) AND (p.is_registered = true))))));
ALTER POLICY friend_requests_select ON public.friend_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: friend_requests
  USING (((from_id = (select auth.uid())) OR (to_id = (select auth.uid()))));
ALTER POLICY friend_requests_update_own ON public.friend_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: friend_requests
  USING ((to_id = (select auth.uid())));
ALTER POLICY ghost_mode_select_own ON public.ghost_mode_active -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: ghost_mode_active
  USING ((((select auth.uid()) = user_id) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY kyc_requests_select_own ON public.kyc_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: kyc_requests
  USING (((user_id = (select auth.uid())) OR (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY message_reactions_delete ON public.message_reactions -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: message_reactions
  USING (((select auth.uid()) = user_id));
ALTER POLICY message_reactions_insert ON public.message_reactions -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: message_reactions
  WITH CHECK ((((select auth.uid()) = user_id) AND ((chat_type = 'room'::text) OR (EXISTS ( SELECT 1
   FROM private_chats pc
  WHERE ((pc.chat_id = message_reactions.chat_id) AND ((select auth.uid()) = ANY (pc.participants))))))));
ALTER POLICY message_reactions_select ON public.message_reactions -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: message_reactions
  USING ((((chat_type = 'room'::text) AND ((select auth.uid()) IS NOT NULL)) OR ((chat_type = 'private'::text) AND (EXISTS ( SELECT 1
   FROM private_chats pc
  WHERE ((pc.chat_id = message_reactions.chat_id) AND ((select auth.uid()) = ANY (pc.participants))))))));
ALTER POLICY messages_insert ON public.messages -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: messages
  WITH CHECK ((((select auth.uid()) = sender_id) AND ((NOT (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = messages.room_id) AND (r.is_private = true))))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = messages.room_id) AND (m.user_id = (select auth.uid())))))) AND _anon_write_ok()));
ALTER POLICY messages_select ON public.messages -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: messages
  USING (((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text) OR (NOT (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = messages.room_id) AND (r.is_private = true))))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = messages.room_id) AND (m.user_id = (select auth.uid())))))));
ALTER POLICY moderator_actions_select ON public.moderator_actions -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: moderator_actions
  USING ((is_chatyuk_admin((select auth.uid())) OR is_country_moderator(scope_value, (select auth.uid()))));
ALTER POLICY moderator_applications_select ON public.moderator_applications -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: moderator_applications
  USING (((uid = (select auth.uid())) OR is_chatyuk_admin((select auth.uid())) OR is_country_moderator(scope_value, (select auth.uid()))));
ALTER POLICY phone_verifications_select_own ON public.phone_verifications -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: phone_verifications
  USING ((uid = (select auth.uid())));
ALTER POLICY photo_slots_unlocked_select_own ON public.photo_slots_unlocked -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: photo_slots_unlocked
  USING ((((select auth.uid()) = user_id) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY photo_unlocks_select_own ON public.photo_unlocks -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: photo_unlocks
  USING ((viewer_id = (select auth.uid())));
ALTER POLICY platform_revenue_admin ON public.platform_revenue -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: platform_revenue
  USING ((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text));
ALTER POLICY point_events_select_own ON public.point_events -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: point_events
  USING ((user_id = (select auth.uid())));
ALTER POLICY post_comments_delete_own ON public.post_comments -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: post_comments
  USING (((select auth.uid()) = author_id));
ALTER POLICY post_comments_insert_own ON public.post_comments -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: post_comments
  WITH CHECK (((select auth.uid()) = author_id));
ALTER POLICY post_likes_delete_own ON public.post_likes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: post_likes
  USING (((select auth.uid()) = user_id));
ALTER POLICY post_likes_insert_own ON public.post_likes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: post_likes
  WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY post_shares_insert_own ON public.post_shares -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: post_shares
  WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY posts_delete_own ON public.posts -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: posts
  USING (((select auth.uid()) = author_id));
ALTER POLICY posts_insert_own ON public.posts -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: posts
  WITH CHECK ((((select auth.uid()) = author_id) AND _anon_write_ok()));
ALTER POLICY posts_select ON public.posts -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: posts
  USING (((NOT (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = (select auth.uid())) AND (p.is_registered = false) AND (NOT (p.id IN ( SELECT du.du
           FROM admin_dummy_uids() du(du)))))))) AND ((visibility = 'public'::text) OR ((visibility = 'followers'::text) AND ((author_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followee_id = posts.author_id) AND (f.follower_id = (select auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM subscriptions s
  WHERE ((s.creator_id = posts.author_id) AND (s.subscriber_id = (select auth.uid())) AND (s.expires_at > now())))))) OR ((visibility = 'subscribers'::text) AND ((author_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM subscriptions s
  WHERE ((s.creator_id = posts.author_id) AND (s.subscriber_id = (select auth.uid())) AND (s.expires_at > now()))))) AND (NOT (EXISTS ( SELECT 1
   FROM blocks b
  WHERE (((b.blocker_id = (select auth.uid())) AND (b.blocked_id = posts.author_id)) OR ((b.blocker_id = posts.author_id) AND (b.blocked_id = (select auth.uid())))))))))));
ALTER POLICY posts_update_own ON public.posts -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: posts
  USING (((select auth.uid()) = author_id));
ALTER POLICY private_chats_insert ON public.private_chats -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: private_chats
  WITH CHECK ((((select auth.uid()) = ANY (participants)) AND (array_length(participants, 1) = 2) AND (participants[1] <> participants[2]) AND (EXISTS ( SELECT 1
   FROM profiles
  WHERE (profiles.id = private_chats.participants[1]))) AND (EXISTS ( SELECT 1
   FROM profiles
  WHERE (profiles.id = private_chats.participants[2])))));
ALTER POLICY private_chats_select ON public.private_chats -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: private_chats
  USING (((select auth.uid()) = ANY (participants)));
ALTER POLICY private_messages_insert ON public.private_messages -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: private_messages
  WITH CHECK ((((select auth.uid()) = sender_id) AND (EXISTS ( SELECT 1
   FROM private_chats pc
  WHERE ((pc.chat_id = private_messages.chat_id) AND ((select auth.uid()) = ANY (pc.participants))))) AND (NOT (EXISTS ( SELECT 1
   FROM (blocks b
     JOIN private_chats pc ON ((pc.chat_id = private_messages.chat_id)))
  WHERE ((b.blocked_id = (select auth.uid())) AND (b.blocker_id = ANY (pc.participants)) AND (b.blocker_id <> (select auth.uid())))))) AND _anon_write_ok()));
ALTER POLICY private_messages_select ON public.private_messages -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: private_messages
  USING ((EXISTS ( SELECT 1
   FROM private_chats pc
  WHERE ((pc.chat_id = private_messages.chat_id) AND (private_messages.chat_id IS NOT NULL) AND (pc.participants @> ARRAY[(select auth.uid())])))));
ALTER POLICY profiles_insert_own ON public.profiles -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: profiles
  WITH CHECK ((((select auth.uid()) = id) AND _anon_write_ok()));
ALTER POLICY random_match_queue_select_own ON public.random_match_queue -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: random_match_queue
  USING ((user_id = (select auth.uid())));
ALTER POLICY referral_clicks_select_own ON public.referral_clicks -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: referral_clicks
  USING ((sharer_id = (select auth.uid())));
ALTER POLICY referral_rewards_select_own ON public.referral_rewards -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: referral_rewards
  USING (((referrer_id = (select auth.uid())) OR (referred_id = (select auth.uid()))));
ALTER POLICY reports_insert_own ON public.reports -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: reports
  WITH CHECK (((select auth.uid()) = reporter_id));
ALTER POLICY reports_select_admin ON public.reports -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: reports
  USING (is_chatyuk_admin((select auth.uid())));
ALTER POLICY rbc_delete_own ON public.room_broadcasters -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_broadcasters
  USING ((user_id = (select auth.uid())));
ALTER POLICY rbc_insert_member ON public.room_broadcasters -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_broadcasters
  WITH CHECK ((EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_broadcasters.room_id) AND (m.user_id = (select auth.uid()))))));
ALTER POLICY rbc_select_member ON public.room_broadcasters -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_broadcasters
  USING ((EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_broadcasters.room_id) AND (m.user_id = (select auth.uid()))))));
ALTER POLICY rjr_insert_own ON public.room_join_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_join_requests
  WITH CHECK ((user_id = (select auth.uid())));
ALTER POLICY rjr_select_own ON public.room_join_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_join_requests
  USING ((user_id = (select auth.uid())));
ALTER POLICY room_poll_votes_select_reader ON public.room_poll_votes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_poll_votes
  USING (((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text) OR (NOT (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_poll_votes.room_id) AND (r.is_private = true))))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_poll_votes.room_id) AND (m.user_id = (select auth.uid())))))));
ALTER POLICY room_presence_delete_own ON public.room_presence -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_presence
  USING (((select auth.uid()) = user_id));
ALTER POLICY room_presence_insert_own ON public.room_presence -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_presence
  WITH CHECK ((((select auth.uid()) = user_id) AND ((NOT (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_presence.room_id) AND (r.is_private = true))))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_presence.room_id) AND (m.user_id = (select auth.uid()))))))));
ALTER POLICY room_presence_update_own ON public.room_presence -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_presence
  USING (((select auth.uid()) = user_id));
ALTER POLICY rs_insert_member ON public.room_signals -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_signals
  WITH CHECK (((from_uid = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_signals.room_id) AND (m.user_id = (select auth.uid())))))));
ALTER POLICY rs_select_member ON public.room_signals -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_signals
  USING ((EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_signals.room_id) AND (m.user_id = (select auth.uid()))))));
ALTER POLICY rvs_insert ON public.room_voice_signals -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_voice_signals
  WITH CHECK (((from_uid = (select auth.uid())) AND ((EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_voice_signals.room_id) AND (COALESCE(r.is_private, false) = false)))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_voice_signals.room_id) AND (m.user_id = (select auth.uid()))))))));
ALTER POLICY rvs_select ON public.room_voice_signals -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_voice_signals
  USING (((EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_voice_signals.room_id) AND (COALESCE(r.is_private, false) = false)))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_voice_signals.room_id) AND (m.user_id = (select auth.uid())))))));
ALTER POLICY rvsp_select ON public.room_voice_speakers -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: room_voice_speakers
  USING (((EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_voice_speakers.room_id) AND (COALESCE(r.is_private, false) = false)))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = room_voice_speakers.room_id) AND (m.user_id = (select auth.uid())))))));
ALTER POLICY rooms_insert ON public.rooms -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: rooms
  WITH CHECK ((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text));
ALTER POLICY rooms_select ON public.rooms -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: rooms
  USING (((NOT is_private) OR ((select auth.uid()) = owner_id) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = rooms.id) AND (m.user_id = (select auth.uid()))))) OR (COALESCE(auth.email(), ''::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY rooms_update ON public.rooms -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: rooms
  USING ((((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text));
ALTER POLICY stories_delete_own ON public.stories -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: stories
  USING ((author_id = (select auth.uid())));
ALTER POLICY stories_insert_own ON public.stories -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: stories
  WITH CHECK (((author_id = (select auth.uid())) AND (( SELECT count(*) AS count
   FROM stories stories_1
  WHERE ((stories_1.author_id = (select auth.uid())) AND (stories_1.created_at >= (now() - '24:00:00'::interval)))) < 10) AND (_viewer_is_registered() OR (visibility = 'everyone'::text))));
ALTER POLICY stories_select ON public.stories -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: stories
  USING (((author_id = (select auth.uid())) OR (((visibility = 'everyone'::text) OR ((visibility = 'followers'::text) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.follower_id = (select auth.uid())) AND (f.followee_id = stories.author_id))))) OR ((visibility = 'friends'::text) AND _are_friends((select auth.uid()), author_id))) AND (NOT (EXISTS ( SELECT 1
   FROM blocks b
  WHERE (((b.blocker_id = (select auth.uid())) AND (b.blocked_id = stories.author_id)) OR ((b.blocker_id = stories.author_id) AND (b.blocked_id = (select auth.uid()))))))))));
ALTER POLICY story_likes_select ON public.story_likes -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: story_likes
  USING (((user_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM stories s
  WHERE ((s.id = story_likes.story_id) AND (s.author_id = (select auth.uid())))))));
ALTER POLICY story_views_insert_own ON public.story_views -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: story_views
  WITH CHECK (((viewer_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM stories s
  WHERE (s.id = story_views.story_id)))));
ALTER POLICY story_views_select ON public.story_views -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: story_views
  USING (((viewer_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM stories s
  WHERE ((s.id = story_views.story_id) AND (s.author_id = (select auth.uid())))))));
ALTER POLICY topup_orders_select_own ON public.topup_orders -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: topup_orders
  USING ((((select auth.uid()) = user_id) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY user_level_state_read_own ON public.user_level_state -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: user_level_state
  USING ((user_id = (select auth.uid())));
ALTER POLICY user_missions_own_select ON public.user_missions -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: user_missions
  USING ((user_id = (select auth.uid())));
ALTER POLICY user_photos_delete_own ON public.user_photos -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: user_photos
  USING (((select auth.uid()) = user_id));
ALTER POLICY user_photos_insert_own ON public.user_photos -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: user_photos
  WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY withdraw_accounts_select_own ON public.withdraw_accounts -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: withdraw_accounts
  USING ((user_id = (select auth.uid())));
ALTER POLICY withdrawal_select_own ON public.withdrawal_requests -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: withdrawal_requests
  USING (((user_id = (select auth.uid())) OR (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text)));
ALTER POLICY yukcoin_consumptions_select_own ON public.yukcoin_consumptions -- SAFE: initplan wrap auth.uid()/jwt(), semantik sama; fitur: yukcoin_consumptions
  USING ((((select auth.uid()) = user_id) OR (((select auth.jwt()) ->> 'email'::text) = 'zunixe@gmail.com'::text)));
