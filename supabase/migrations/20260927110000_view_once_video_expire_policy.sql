-- ============================================================
-- View-once VIDEO: izinkan penerima menandai `video_once_expired`.
--
-- MASALAH: video "sekali lihat" (type='video_once') ditandai sudah ditonton
-- oleh PENERIMA dengan mengubah type → 'video_once_expired'. Tapi policy
-- `private_messages_update_view_once` hanya mengizinkan type =
-- 'view_once_expired' (foto). Akibatnya update video DITOLAK RLS (0 baris)
-- → type tetap 'video_once' → penerima bisa memutar ulang SELAMANYA
-- (beda dari foto yang terkunci setelah ditonton).
--
-- PERBAIKAN: perluas WITH CHECK policy supaya menerima juga
-- 'video_once_expired' (private_messages & messages untuk room).
-- Qual (siapa yang boleh) TIDAK diubah: tetap peserta chat.
--
-- Idempotent (drop policy if exists lalu create ulang). Tidak menyentuh
-- fungsi FROZEN. CARA APPLY: Management API.
-- ============================================================

-- ── private_messages ──
drop policy if exists private_messages_update_view_once on public.private_messages; -- SAFE: tabel bersama private_messages; perluas WITH CHECK (view_once_expired + video_once_expired) — fitur terdampak: private chat view-once; qual peserta chat tak berubah
create policy private_messages_update_view_once on public.private_messages -- SAFE: perluas view-once video; tidak melonggarkan siapa yang boleh update
  for update
  using (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any(pc.participants)
    )
  )
  with check (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any(pc.participants)
    )
    and type in ('view_once_expired', 'video_once_expired')
  );

-- ── messages (room) ──
-- Room belum punya policy expire view-once sama sekali → penerima tidak
-- pernah bisa menandai (foto ATAU video) sudah ditonton. Ikut logika
-- messages_select: global room (is_private=false) siapa pun yang login;
-- private room → harus member.
drop policy if exists messages_update_view_once on public.messages; -- SAFE: tabel bersama messages (room); tambah policy expire view-once baru; qual mengikuti messages_select
create policy messages_update_view_once on public.messages -- SAFE: policy baru view-once room; tidak melonggarkan akses
  for update
  using (
    (not exists (
      select 1 from public.rooms r
      where r.id = messages.room_id and r.is_private = true
    ))
    or exists (
      select 1 from public.room_members m
      where m.room_id = messages.room_id and m.user_id = auth.uid()
    )
  )
  with check (
    (
      (not exists (
        select 1 from public.rooms r
        where r.id = messages.room_id and r.is_private = true
      ))
      or exists (
        select 1 from public.room_members m
        where m.room_id = messages.room_id and m.user_id = auth.uid()
      )
    )
    and type in ('view_once_expired', 'video_once_expired')
  );
