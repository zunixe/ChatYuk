-- ============================================================
-- "Putus teman" (unfollow) WAJIB benar-benar memutus di SEMUA definisi teman.
--
-- LATAR: ada DUA definisi "teman" di sistem:
--   1. `_privacy_are_friends` = mutual `follows` (dipakai privasi: presence/
--      photo/about/story/leaderboard via privacy_can_view).
--   2. `_are_friends` = `friend_requests.status = 'accepted'` (dipakai
--      story_tray / story_slides / mark_story_seen).
--   `respond_friend_request(accept)` membuat KEDUANYA (status accepted +
--   2 baris `follows`). TAPI `unfollow_user` DULU hanya menghapus `follows`
--   → baris `friend_requests` accepted DIBIARKAN → `_are_friends` tetap
--   TRUE setelah putus teman. Akibat: **story** mantan teman masih terlihat
--   (stale). (Top Aktif & field privasi lain sudah benar karena pakai
--   `_privacy_are_friends`.)
--
-- FIX: `unfollow_user` juga menghapus baris `friend_requests` (accepted &
--   pending, kedua arah) antara me & followee → kedua definisi konsisten.
--
-- Sumber disalin PERSIS dari live + 1 blok DELETE. Bukan FROZEN.
-- CARA APPLY: Management API (1 statement create fn).
-- ============================================================

create or replace function public.unfollow_user(p_followee uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_followee is null then raise exception 'Invalid target'; end if;
  delete from follows where follower_id = me and followee_id = p_followee;
  -- Putus teman = benar-benar putus: hapus relasi friend_requests accepted
  -- maupun pending antara kedua pihak, supaya `_are_friends` (friend_requests
  -- accepted) SELARAS dengan `_privacy_are_friends` (follows). Tanpa ini,
  -- story mantan teman tetap terlihat (stale).
  delete from friend_requests
   where (from_id = me and to_id = p_followee)
      or (from_id = p_followee and to_id = me);
  return jsonb_build_object('ok', true, 'following', false);
end;
$function$;

-- Verifikasi setelah apply:
--   -- accept friend A<->B → unfollow → _are_friends & _privacy_are_friends = false
--   select public._are_friends('<A>','<B>'), public._privacy_are_friends('<A>','<B>');
