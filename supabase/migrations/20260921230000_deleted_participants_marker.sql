-- menyentuh: (tidak ada fungsi FROZEN — hanya helper baru + penulisan ulang
-- fungsi hapus-akun yang sudah lama tidak frozen)

-- ============================================================
-- Penanda "peserta sudah dihapus" pada private_chats.
--
-- MASALAH: saat akun dihapus (self-delete / admin hapus anon / hapus dummy /
-- purge), baris `private_chats` ikut DIHAPUS. Akibatnya lawan bicara hanya
-- melihat chat itu hilang mendadak tanpa penjelasan — dan kalau pengirim
-- masih melihat centang-2 lama di cache, tampak seolah pesannya terkirim
-- padahal tidak ada perangkat lawan yang menerimanya.
--
-- SOLUSI: baris chat DIPERTAHANKAN dengan penanda `deleted_participants`,
-- ISI PESAN DIHAPUS (privasi: isi percakapan tidak tinggal di server atas
-- nama user yang sudah pergi). Klien menampilkan label "Akun dihapus",
-- mengunci kirim, dan user boleh menghapus chat itu sendiri.
--
-- CATATAN: admin_delete_chat (hapus chat dari monitor) TIDAK diubah —
-- itu memang penghapusan chat eksplisit, bukan penghapusan akun.
-- ============================================================

-- ── 1. Kolom penanda ──
alter table public.private_chats
  add column if not exists deleted_participants uuid[] not null default '{}';

-- ── 2. Helper terpusat: tandai chat + bersihkan isi percakapan ──
-- Dipakai SEMUA jalur penghapusan akun supaya perilakunya seragam. Idempoten:
-- uid yang sudah ada di penanda tidak digandakan (distinct).
create or replace function public.mark_chats_user_deleted(p_uid uuid)
returns int
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_n int := 0;
begin
  if p_uid is null then return 0; end if;

  -- Hapus SELURUH isi percakapan di chat yang melibatkan user ini (kedua
  -- sisi) — termasuk pesan lawan, karena tujuannya menghapus ISI, bukan
  -- sekadar pesan milik user yang pergi.
  delete from public.private_messages pm
   using public.private_chats pc
   where pm.chat_id = pc.chat_id
     and pc.participants @> array[p_uid]::uuid[];

  -- Pertahankan baris chat + pasang penanda; kosongkan metadata preview
  -- supaya tidak ada sisa teks yang bocor ke kartu list.
  --
  -- PENTING: `message_count` SENGAJA tidak dinolkan. Klien menyaring chat
  -- dengan `messageCount > 0` (chat_service_private_chatlist.dart) — kalau
  -- dinolkan, baris ini justru ikut terbuang dari daftar dan label "Akun
  -- dihapus" tidak akan pernah terlihat (membatalkan tujuan fitur).
  update public.private_chats pc
     set deleted_participants = (
           select coalesce(array_agg(distinct x), '{}'::uuid[])
           from unnest(pc.deleted_participants || array[p_uid]) as x
         ),
         last_message = '',
         last_sender_id = null,
         unread_counts = '{}'::jsonb,
         last_read_at = '{}'::jsonb
   where pc.participants @> array[p_uid]::uuid[];
  get diagnostics v_n = row_count;
  return v_n;
end;
$fn$;

revoke execute on function public.mark_chats_user_deleted(uuid) from public, anon;
grant execute on function public.mark_chats_user_deleted(uuid)
  to authenticated, service_role;

-- ── 3. delete_my_account: pertahankan chat lawan sebagai penanda ──
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

  -- user_devices SENGAJA tidak dihapus (hardware milik install, FK SET NULL).

  delete from public.profiles where id = v_uid;
  delete from auth.users where id = v_uid;

  return jsonb_build_object('ok', true, 'deleted_chats', v_deleted_chats);
end;
$fn$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ── 4. admin_delete_anon_user: idem ──
create or replace function public.admin_delete_anon_user(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_is_reg boolean;
  v_is_dummy boolean;
  v_nick text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(p.is_registered, false), coalesce(p.nickname, '')
    into v_is_reg, v_nick
    from public.profiles p
   where p.id = p_uid;

  if v_nick = '' and not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  -- Cek DUMMY lebih dulu: dummy bisa `is_registered=true` (dibuat admin).
  select exists(select 1 from public.dummy_accounts d where d.uid = p_uid)
    into v_is_dummy;
  if v_is_dummy then
    return jsonb_build_object('ok', false, 'error', 'DUMMY');
  end if;

  if v_is_reg then
    return jsonb_build_object('ok', false, 'error', 'REGISTERED');
  end if;

  perform public.fn_archive_deleted_user(p_uid, 'admin_delete');

  -- Chat lawan dipertahankan sebagai penanda (isi pesan dihapus).
  perform public.mark_chats_user_deleted(p_uid);

  delete from public.room_presence where user_id = p_uid;
  delete from public.blocks where blocker_id = p_uid or blocked_id = p_uid;
  delete from public.reports where reporter_id = p_uid or reported_id = p_uid;
  delete from public.user_photos where user_id = p_uid;
  delete from public.user_devices where user_id = p_uid;
  delete from public.user_location_history where user_id = p_uid;
  delete from public.contact_messages where user_id = p_uid;

  delete from public.profiles where id = p_uid;

  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from auth.users where id = p_uid;

  delete from public.admin_stats_cache where id = 1;

  return jsonb_build_object('ok', true, 'nickname', v_nick);
end;
$fn$;

revoke execute on function public.admin_delete_anon_user(uuid) from public, anon;
grant execute on function public.admin_delete_anon_user(uuid)
  to authenticated, service_role;

-- ── 5. admin_delete_dummy: idem ──
create or replace function public.admin_delete_dummy(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_chats int;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  perform public.fn_archive_deleted_user(p_uid, 'dummy_delete');

  -- Chat lawan dipertahankan sebagai penanda (isi pesan dihapus).
  v_chats := public.mark_chats_user_deleted(p_uid);

  delete from public.room_presence where user_id = p_uid;
  delete from public.user_photos where user_id = p_uid;

  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from public.dummy_accounts where uid = p_uid;
  delete from auth.users where id = p_uid;

  return jsonb_build_object('ok', true, 'chats_deleted', v_chats);
end;
$function$;

revoke execute on function public.admin_delete_dummy(uuid) from public, anon;
grant execute on function public.admin_delete_dummy(uuid)
  to authenticated, service_role;

-- ── 6. purge_inactive_accounts: idem ──
create or replace function public.purge_inactive_accounts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cutoff timestamptz := now() - interval '90 days';
  deleted int := 0;
  r record;
begin
  for r in
    select id from public.profiles
    where last_seen < cutoff
      and last_seen is not null
      and id not in (select id from public.profiles where is_registered = true and points > 10000)
  loop
    begin
      perform public.fn_archive_deleted_user(r.id);
    exception when others then null;
    end;

    -- Chat lawan dipertahankan sebagai penanda (isi pesan dihapus).
    perform public.mark_chats_user_deleted(r.id);

    delete from public.follows where follower_id = r.id or followee_id = r.id;
    delete from public.friend_requests where from_id = r.id or to_id = r.id;
    delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
    delete from public.subscriptions where subscriber_id = r.id or creator_id = r.id;
    delete from public.room_messages where sender_id = r.id;
    delete from public.private_messages where sender_id = r.id;
    delete from public.room_presence where user_id = r.id;
    delete from public.profiles where id = r.id;
    deleted := deleted + 1;
    exit when deleted >= 100;
  end loop;
  return jsonb_build_object('deleted', deleted, 'cutoff', cutoff);
end; $$;

revoke execute on function public.purge_inactive_accounts() from public, anon;
grant execute on function public.purge_inactive_accounts() to authenticated, service_role;
