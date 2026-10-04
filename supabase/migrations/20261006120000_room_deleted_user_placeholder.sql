-- ============================================================
-- Pesan room milik user yang dihapus tampil "Pesan dihapus".
--
-- PERMINTAAN USER: kalau user dihapus (admin) atau menghapus sendiri,
-- pesan-pesan yang dibuatnya di room HARUS tampil terhapus juga.
--
-- MASALAH: `delete_my_account` me-HARD-delete baris `messages` milik user
-- (pesan lenyap total), dan purge/jalur hapus lain meninggalkan pesan yatim
-- yang tampil normal. Klien (RoomMessageBubble) sudah me-render placeholder
-- "Pesan dihapus" dari flag `is_deleted` — yang kurang hanya flag-nya.
--
-- PERUBAHAN (idempotent, create or replace):
--   1. `delete_my_account`: pesan room di-SOFT-delete
--      (`is_deleted = true`), bukan hard-delete.
--   2. `purge_onboarding_placeholders`: tambah soft-delete pesan room di
--      loop per-user (sebelum hapus profiles).
--   3. Backfill SEKALI: pesan room yatim (sender tanpa profiles) yang masih
--      `is_deleted = false` → tandai terhapus.
--
-- Tidak FROZEN (cek frozen_functions.txt). Grants tidak diubah
-- (create or replace mempertahankan privilege).
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Pesan room: SOFT-delete (is_deleted) supaya tampil "Pesan dihapus"
  -- di room — JANGAN hard-delete (pesan hilang total). Klien me-render
  -- placeholder dari flag ini (RoomMessageBubble). Isi teks tetap di DB
  -- (konsisten dgn pesan yang dihapus sendiri); arsip sudah dibuat di atas.
  update public.messages set is_deleted = true where sender_id = v_uid;
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
$function$
;

CREATE OR REPLACE FUNCTION public.purge_onboarding_placeholders(p_min_age_hours integer DEFAULT 24, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ids uuid[];
  v_count int := 0;
  v_uid uuid;
begin
  -- Kandidat: placeholder trigger yang benar-benar tak pernah dipakai.
  select coalesce(array_agg(p.id), '{}')
    into v_ids
    from public.profiles p
   where p.nickname ~ '^Anon[0-9A-F]+$'           -- (1) pola trigger
     and coalesce(p.needs_onboarding, false) = true  -- (2) belum onboarding
     and coalesce(p.is_registered, false) = false     -- (3) bukan akun email
     and p.last_seen = p.created_at                    -- (4) belum pernah aktif
     and p.created_at < now() - make_interval(hours => p_min_age_hours)  -- (6)
     and not exists (select 1 from public.dummy_accounts d where d.uid = p.id) -- (7)
     -- (5) tanpa jejak berharga apa pun:
     and not exists (select 1 from public.user_devices dv where dv.user_id = p.id)
     and not exists (select 1 from public.user_location_history l where l.user_id = p.id)
     and not exists (select 1 from public.private_messages m where m.sender_id = p.id)
     and not exists (select 1 from public.private_chats c where c.participants @> array[p.id]::uuid[])
     and not exists (select 1 from public.coin_ledger k where k.user_id = p.id)
     and not exists (select 1 from public.point_events e where e.user_id = p.id)
     and not exists (select 1 from public.stories s where s.author_id = p.id)
     and not exists (select 1 from public.posts po where po.author_id = p.id)
     and not exists (select 1 from public.follows f where f.follower_id = p.id or f.followee_id = p.id)
     and not exists (select 1 from public.friend_requests fr where fr.from_id = p.id or fr.to_id = p.id)
     and not exists (select 1 from public.user_photos ph where ph.user_id = p.id)
     and not exists (select 1 from public.blocks b where b.blocker_id = p.id or b.blocked_id = p.id)
     and not exists (select 1 from public.reports r where r.reporter_id = p.id or r.reported_id = p.id)
     and not exists (select 1 from public.contact_messages cm where cm.user_id = p.id);

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'count', coalesce(array_length(v_ids, 1), 0),
      'ids', to_jsonb(v_ids)
    );
  end if;

  -- Hapus satu per satu; satu kegagalan tidak menggagalkan sisanya.
  foreach v_uid in array v_ids loop
    begin
      perform public.fn_archive_deleted_user(v_uid, 'onboarding_placeholder');
      delete from public.room_presence where user_id = v_uid;
      delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
      delete from public.reports where reporter_id = v_uid or reported_id = v_uid;
      delete from public.user_photos where user_id = v_uid;
      delete from public.private_messages pm
        using public.private_chats pc
        where pm.chat_id = pc.chat_id and pc.participants @> array[v_uid]::uuid[];
      delete from public.private_chats pc where pc.participants @> array[v_uid]::uuid[];
      delete from public.private_messages where sender_id = v_uid;
      -- Pesan room: SOFT-delete supaya tampil "Pesan dihapus" (bukan hilang).
      update public.messages set is_deleted = true where sender_id = v_uid;
      -- Device & location WAJIB dihapus SEBELUM profiles (FK SET NULL tapi
      -- kolom NOT NULL → 23503 bila profiles lebih dulu).
      delete from public.user_devices where user_id = v_uid;
      delete from public.user_location_history where user_id = v_uid;
      delete from public.contact_messages where user_id = v_uid;
      delete from public.profiles where id = v_uid;
      -- Ledger koin & point_events: trigger append-only menolak DELETE.
      alter table public.coin_ledger disable trigger coin_ledger_no_delete;
      delete from public.coin_ledger where user_id = v_uid;
      alter table public.coin_ledger enable trigger coin_ledger_no_delete;
      delete from public.point_events where user_id = v_uid;
      delete from auth.users where id = v_uid;
      v_count := v_count + 1;
    exception when others then
      -- Satu user gagal (mis. data aneh) tidak menggagalkan seluruh run.
      -- Pastikan trigger coin_ledger kembali ENABLE walau error di tengah.
      begin
        alter table public.coin_ledger enable trigger coin_ledger_no_delete;
      exception when others then null;
      end;
    end;
  end loop;

  return jsonb_build_object(
    'dry_run', false,
    'count', v_count,
    'candidates', coalesce(array_length(v_ids, 1), 0)
  );
end;
$function$
;

-- ── 3. Backfill pesan yatim ──
-- SAFE: hanya menandai is_deleted pada pesan room yang sender-nya sudah
-- tidak punya baris profiles (akun terhapus); tidak menyentuh pesan user
-- aktif, tidak menghapus baris.
UPDATE public.messages m
   SET is_deleted = true
 WHERE m.is_deleted = false
   AND NOT EXISTS (select 1 from public.profiles p where p.id = m.sender_id);
