-- ============================================================
-- ChatYuk: Fix view-once photo expired
-- private_messages hanya punya policy SELECT + INSERT.
-- clearViewOnceImage() meng-update row (hapus image_data + ubah type),
-- tapi ditolak RLS karena tidak ada policy UPDATE.
-- Akibatnya foto view-once tidak pernah benar-benar dihapus dari DB,
-- sehingga setelah keluar-masuk chat foto bisa dilihat lagi.
--
-- Jalankan di: Supabase Dashboard > SQL Editor > Run
-- Catatan: JANGAN pakai `new.` di with check — error 42P01.
--         Pakai referensi kolom langsung (type, image_data).
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
    -- Batasi: update hanya boleh menghasilkan pesan view_once expired tanpa foto
    and type = 'view_once_expired'
    and image_data = ''
  );
