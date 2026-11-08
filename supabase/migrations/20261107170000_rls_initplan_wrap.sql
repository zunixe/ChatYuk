-- menyentuh: (RLS policy saja, tidak menyentuh fungsi)
-- Sumber: docs/LINT_FIX_PLAN.md P1 (audit Advisors 2026-11-07).
-- Perf initplan: auth.uid()/auth.jwt() dibungkus (select ...) agar dievaluasi
-- sekali per statement, bukan per baris. Semantik policy TIDAK berubah.
-- Fitur terdampak (docs/FEATURE_MAP.md): chat (private_messages,
-- private_chats, messages, starred_messages), call (calls), profil (profiles,
-- profile_privacy_exclusions), room (room_reads), device (user_devices),
-- admin (admin_alerts, deleted_users).
-- Uji di replica 43: 13/13 ALTER OK + smoke_anon_register OK bersih.

ALTER POLICY starred_messages_owner ON public.starred_messages -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: starred
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY calls_update ON public.calls -- SAFE: initplan wrap auth.uid()/auth.jwt(), semantik sama; fitur: call
  USING (((select auth.uid()) = caller_id) OR ((select auth.uid()) = callee_id)
         OR (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text))
  WITH CHECK (((select auth.uid()) = caller_id) OR ((select auth.uid()) = callee_id)
         OR (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text));

ALTER POLICY messages_update_own ON public.messages -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: chat room
  USING ((select auth.uid()) = sender_id)
  WITH CHECK ((select auth.uid()) = sender_id);

ALTER POLICY messages_update_view_once ON public.messages -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: chat room
  USING ((NOT (EXISTS (SELECT 1 FROM rooms r
          WHERE ((r.id = messages.room_id) AND (r.is_private = true)))))
         OR (EXISTS (SELECT 1 FROM room_members m
          WHERE ((m.room_id = messages.room_id) AND (m.user_id = (select auth.uid()))))))
  WITH CHECK ((NOT (EXISTS (SELECT 1 FROM rooms r
          WHERE ((r.id = messages.room_id) AND (r.is_private = true)))))
         OR (EXISTS (SELECT 1 FROM room_members m
          WHERE ((m.room_id = messages.room_id) AND (m.user_id = (select auth.uid())))))
         AND (type = ANY (ARRAY['view_once_expired'::text, 'video_once_expired'::text])));

ALTER POLICY profile_privacy_exclusions_own ON public.profile_privacy_exclusions -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: privasi profil
  USING (owner_id = (select auth.uid()))
  WITH CHECK (owner_id = (select auth.uid()));

ALTER POLICY profiles_update_own ON public.profiles -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: profil
  USING ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);

ALTER POLICY private_chats_update ON public.private_chats -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: chat
  USING ((select auth.uid()) = ANY (participants))
  WITH CHECK ((select auth.uid()) = ANY (participants));

ALTER POLICY private_messages_update ON public.private_messages -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: chat
  USING (((select auth.uid()) = sender_id) AND (EXISTS (SELECT 1 FROM private_chats pc
          WHERE ((pc.chat_id = private_messages.chat_id) AND ((select auth.uid()) = ANY (pc.participants))))))
  WITH CHECK ((select auth.uid()) = sender_id);

ALTER POLICY private_messages_update_view_once ON public.private_messages -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: chat
  USING (EXISTS (SELECT 1 FROM private_chats pc
          WHERE ((pc.chat_id = private_messages.chat_id) AND ((select auth.uid()) = ANY (pc.participants)))))
  WITH CHECK ((EXISTS (SELECT 1 FROM private_chats pc
          WHERE ((pc.chat_id = private_messages.chat_id) AND ((select auth.uid()) = ANY (pc.participants)))))
         AND (type = ANY (ARRAY['view_once_expired'::text, 'video_once_expired'::text])));

ALTER POLICY room_reads_own ON public.room_reads -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: room
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY user_devices_own ON public.user_devices -- SAFE: initplan wrap auth.uid(), semantik sama; fitur: device/FCM
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- Tambahan hasil verifikasi: 2 policy yang memakai auth.jwt() langsung.
ALTER POLICY admin_alerts_admin ON public.admin_alerts -- SAFE: initplan wrap auth.jwt(), semantik sama; fitur: admin
  USING (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text)
  WITH CHECK (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text);

ALTER POLICY deleted_users_admin ON public.deleted_users -- SAFE: initplan wrap auth.jwt(), semantik sama; fitur: admin
  USING (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text)
  WITH CHECK (COALESCE(((select auth.jwt()) ->> 'email'::text), ''::text) = 'zunixe@gmail.com'::text);
