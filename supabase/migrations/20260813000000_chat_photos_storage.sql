-- ============================================================
-- ChatYuk: Supabase Storage untuk foto chat
-- Foto di-upload ke bucket `chat-photos`, DB hanya simpan path
-- (mis. 'chat/<chatId>/<msgId>.jpg'). Menghemat DB drastis.
--
-- Bucket dibuat via migration (storage.objects). RLS:
-- - INSERT: pemilik chat (authenticated) boleh upload
-- - SELECT: peserta chat boleh download (via bucket public read)
-- ============================================================

-- Buat bucket chat-photos (public read — path berisi UUID, aman).
insert into storage.buckets (id, name, public)
values ('chat-photos', 'chat-photos', true)
on conflict (id) do nothing;

-- Izinkan siapa pun (authenticated) membaca objek — path sudah acak/UUID.
create policy "chat_photos_public_read" on storage.objects
  for select using (bucket_id = 'chat-photos');

-- Authenticated boleh upload (nama objek berisi chatId + msgId).
create policy "chat_photos_authenticated_insert" on storage.objects
  for insert with check (bucket_id = 'chat-photos' and auth.role() = 'authenticated');

-- Pemilik bisa hapus (admin/moderation). Bucket public.
create policy "chat_photos_authenticated_delete" on storage.objects
  for delete using (bucket_id = 'chat-photos' and auth.role() = 'authenticated');
