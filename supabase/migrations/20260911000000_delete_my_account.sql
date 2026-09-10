-- Hapus akun oleh user sendiri (Google Play: account deletion requirement).
-- Menepati janji Pasal 13 Syarat & Ketentuan: "Anda dapat menghapus Akun
-- Anda kapan pun melalui menu pengaturan profil dalam Aplikasi."
--
-- Dipanggil dari profile screen via rpc('delete_my_account').
-- Kontrak:
--   - hanya user login (authenticated); anon & registered sama-sama boleh.
--   - admin (zunixe@gmail.com) DITOLAK — akun admin tidak boleh self-delete.
--   - arsip dulu ke deleted_users (fn_archive_deleted_user sudah ada).
--   - bersihkan semua data pribadi lalu auth user (cascade FK menangani
--     tabel yang mereferensi profiles(id)/auth.users(id) on delete cascade).

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

  -- Admin dilarang hapus akun sendiri (harus lewat panel admin).
  if coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com' then
    raise exception 'ADMIN_DELETE_FORBIDDEN';
  end if;

  -- Profil wajib ada — kalau tidak, sesi tidak valid untuk dihapus.
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  -- 1. Arsip (deleted_users) — snapshot nickname/email/device sebelum hapus.
  perform public.fn_archive_deleted_user(v_uid, 'self_delete');

  -- 2. Relasi sosial
  delete from public.follows where follower_id = v_uid or followee_id = v_uid;
  delete from public.friend_requests where from_id = v_uid or to_id = v_uid;
  delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
  delete from public.subscriptions where subscriber_id = v_uid or creator_id = v_uid;

  -- 3. Chat 1:1 yang melibatkan user (private_chats tidak punya kolom
  --    owner — 1:1 simetris). Chat ikut terhapus meski partisipan lain
  --    masih ada (menjaga privasi: isi percakapan tidak boleh tinggal
  --    di server atas nama user yang sudah hapus akun).
  delete from public.private_chats
  where participants @> array[v_uid]::uuid[];
  get diagnostics v_deleted_chats = row_count;

  -- 4. Pesan & konten
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

  -- 5. Ledger koin & panggilan — FK ke auth.users on delete cascade, tapi
  --    dihapus eksplisit supaya urutan deterministik (tidak bergantung
  --    urutan evaluasi cascade antar tabel).
  delete from public.coin_ledger where user_id = v_uid;
  delete from public.point_events where user_id = v_uid;
  delete from public.calls where caller_id = v_uid or callee_id = v_uid;
  delete from public.call_signals where from_uid = v_uid;

  -- 6. JANGAN hapus user_devices — hardware milik install, FK sudah SET NULL
  --    saat profil dihapus; data device dipakai deteksi multi-akun/abuse
  --    (sama seperti alur purge cron). Token FCM yatim tidak akan menerima
  --    push lagi karena join selalu lewat user_id.

  -- 7. Hapus profil + auth user (FK cascade menangani sisanya, mis.
  --    reports yang mereferensi).
  delete from public.profiles where id = v_uid;
  delete from auth.users where id = v_uid;

  return jsonb_build_object('ok', true, 'deleted_chats', v_deleted_chats);
end;
$fn$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
