-- ============================================================
-- ChatYuk: Admin dapat melihat foto view-once yang sudah expired.
-- Sebelumnya clearViewOnceImage() menghapus image_data (set '')
-- sehingga foto hilang permanen dari DB — admin tidak bisa melihat.
--
-- Sekarang image_data DIKEEP di DB saat expired. Hanya type yang
-- diubah ke 'view_once_expired'. Kontrol "boleh lihat/tidak"
-- dilakukan di sisi UI:
--   - User biasa: type view_once_expired -> kartu terkunci
--   - Admin view: type view_once_expired -> tetap decode & tampil
--
-- Perubahan policy: hapus constraint `image_data = ''` pada
-- with check, tetap batasi agar update hanya menghasilkan
-- type='view_once_expired' (anti abuse injeksi foto).
-- ============================================================

drop policy if exists "private_messages_update_view_once" on public.private_messages;

create policy "private_messages_update_view_once" on public.private_messages
  for update
  using (
    -- Hanya peserta chat yang bisa meng-update pesan di chat-nya
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
  )
  with check (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Batasi: update hanya boleh menghasilkan pesan view_once expired
    -- (image_data DIPERTAHANKAN agar admin bisa melihatnya)
    and type = 'view_once_expired'
  );
