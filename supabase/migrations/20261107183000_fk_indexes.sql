-- Sumber: docs/LINT_FIX_PLAN.md P3 (audit FK tanpa index 2026-11-07).
-- 25 FK single-kolom tanpa index leading-column. Semua tabel masih kecil —
-- index murah sekarang, mencegah full-scan join/cascade saat tabel besar.
-- CONCURRENTLY: tidak blok tulisan production (jalan satu-per-satu di luar
-- transaksi — via API dikirim per statement).

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_bonus_claims_user_id ON public.bonus_claims (user_id); -- SAFE: index FK bonus_claims.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_poll_votes_user_id ON public.chat_poll_votes (user_id); -- SAFE: index FK chat_poll_votes.user_id -> auth.users
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_comment_likes_user_id ON public.comment_likes (user_id); -- SAFE: index FK comment_likes.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_comment_shares_user_id ON public.comment_shares (user_id); -- SAFE: index FK comment_shares.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_contact_messages_user_id ON public.contact_messages (user_id); -- SAFE: index FK contact_messages.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_kyc_requests_reviewed_by ON public.kyc_requests (reviewed_by); -- SAFE: index FK kyc_requests.reviewed_by -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_moderator_applications_uid ON public.moderator_applications (uid); -- SAFE: index FK moderator_applications.uid -> auth.users
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_photo_unlocks_photo_id ON public.photo_unlocks (photo_id); -- SAFE: index FK photo_unlocks.photo_id -> user_photos
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_comments_author_id ON public.post_comments (author_id); -- SAFE: index FK post_comments.author_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_comments_parent_id ON public.post_comments (parent_id); -- SAFE: index FK post_comments.parent_id -> post_comments
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_likes_user_id ON public.post_likes (user_id); -- SAFE: index FK post_likes.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_shares_user_id ON public.post_shares (user_id); -- SAFE: index FK post_shares.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_profile_privacy_exclusions_excluded_uid ON public.profile_privacy_exclusions (excluded_uid); -- SAFE: index FK profile_privacy_exclusions.excluded_uid -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_profiles_referred_by ON public.profiles (referred_by); -- SAFE: index FK profiles.referred_by -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_random_match_pairs_b ON public.random_match_pairs (b); -- SAFE: index FK random_match_pairs.b -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_random_match_queue_matched_call_id ON public.random_match_queue (matched_call_id); -- SAFE: index FK random_match_queue.matched_call_id -> calls
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_random_match_queue_matched_with ON public.random_match_queue (matched_with); -- SAFE: index FK random_match_queue.matched_with -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_room_broadcasters_user_id ON public.room_broadcasters (user_id); -- SAFE: index FK room_broadcasters.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_room_join_requests_user_id ON public.room_join_requests (user_id); -- SAFE: index FK room_join_requests.user_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_room_poll_votes_user_id ON public.room_poll_votes (user_id); -- SAFE: index FK room_poll_votes.user_id -> auth.users
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_room_reads_room_id ON public.room_reads (room_id); -- SAFE: index FK room_reads.room_id -> rooms
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_story_mutes_muted_id ON public.story_mutes (muted_id); -- SAFE: index FK story_mutes.muted_id -> profiles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_topup_orders_package_id ON public.topup_orders (package_id); -- SAFE: index FK topup_orders.package_id -> topup_packages
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_missions_mission_id ON public.user_missions (mission_id); -- SAFE: index FK user_missions.mission_id -> missions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_withdrawal_requests_reviewed_by ON public.withdrawal_requests (reviewed_by); -- SAFE: index FK withdrawal_requests.reviewed_by -> profiles
