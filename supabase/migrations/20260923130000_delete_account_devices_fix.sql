-- ============================================================
-- FIX: delete_my_account() gagal 23502 untuk user yg punya device row.
--
-- Insiden 2026-09-23 (laporan: hapus akun anon "hdjdjfj" selalu gagal):
--   null value in column "user_id" of relation "user_devices"
--   violates not-null constraint
--   CONTEXT: UPDATE user_devices SET user_id = NULL ... (FK SET NULL)
--            saat `delete from public.profiles`.
--
-- Akar: FK user_devices.user_id dan user_location_history.user_id memang
-- SET NULL on delete, TAPI kolomnya sendiri NOT NULL. Komentar lama
-- ("hardware milik install, FK SET NULL") salah asumsi — SET NULL selalu
-- meledak begitu ada baris milik user yg dihapus. Akun tanpa device row
-- (kasus uji awal) lolos, sehingga bug tak terdeteksi.
--
-- Fix: hapus eksplisit baris device + location history milik user SEBELUM
-- `delete from profiles`. Selaras privasi (hapus akun = hapus jejak) dan
-- Google Play account-deletion requirement. Hardware re-register otomatis
-- via syncToServer saat login berikutnya; exclusion admin berbasis
-- install_id tersimpan di tabel lain, tidak ikut terhapus.
-- Bukan fungsi FROZEN (tidak ada di scripts/frozen_functions.txt).
-- ============================================================

create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_deleted_chats int := 0;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com' then
    raise exception 'ADMIN_DELETE_FORBIDDEN';
  end if;

  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  perform public.fn_archive_deleted_user(v_uid, 'self_delete');

  -- Relasi sosial
  delete from public.follows where follower_id = v_uid or followee_id = v_uid;
  delete from public.friend_requests where from_id = v_uid or to_id = v_uid;
  delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
  delete from public.subscriptions where subscriber_id = v_uid or creator_id = v_uid;

  -- Chat 1:1: baris DIPERTAHANKAN + ditandai; ISI PESAN dihapus.
  -- Lawan melihat label "Akun dihapus" dan bisa menghapusnya sendiri.
  v_deleted_chats := public.mark_chats_user_deleted(v_uid);

  -- Pesan & konten
  delete from public.private_messages where sender_id = v_uid;
  delete from public.messages where sender_id = v_uid;
  delete from public.room_members where user_id = v_uid;
  delete from public.room_join_requests where user_id = v_uid;
  delete from public.room_presence where user_id = v_uid;
  delete from public.stories where author_id = v_uid;
  delete from public.story_views where viewer_id = v_uid;
  delete from public.user_photos where user_id = v_uid;
  delete from public.photo_unlocks where viewer_id = v_uid;
  delete from public.posts where author_id = v_uid;
  delete from public.post_comments where author_id = v_uid;
  delete from public.comment_likes where user_id = v_uid;
  delete from public.post_likes where user_id = v_uid;
  delete from public.comment_shares where user_id = v_uid;
  delete from public.post_shares where user_id = v_uid;

  -- Ledger koin: trigger append-only menolak DELETE → matikan sementara.
  set local session_replication_role = 'replica';
  delete from public.coin_ledger where user_id = v_uid;
  delete from public.point_events where user_id = v_uid;
  set local session_replication_role = 'origin';
  delete from public.calls where caller_id = v_uid or callee_id = v_uid;
  delete from public.call_signals where from_uid = v_uid;

  -- Device & location history: FK-nya SET NULL tapi kolom user_id NOT NULL
  -- → hapus eksplisit SEBELUM profiles (lihat header file).
  delete from public.user_devices where user_id = v_uid;
  delete from public.user_location_history where user_id = v_uid;

  delete from public.profiles where id = v_uid;
  delete from auth.users where id = v_uid;

  return jsonb_build_object('ok', true, 'deleted_chats', v_deleted_chats);
end;
$fn$;

-- Grant tidak diubah (sudah benar: EXECUTE untuk authenticated).
