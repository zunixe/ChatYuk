-- Storage UPDATE policy untuk bucket chat-photos
-- uploadAvatar pakai FileOptions(upsert: true) yang trigger UPDATE saat
-- object sudah ada → sebelumnya gagal 'function is not unique' /
-- 'new row violates row-level security policy' karena tidak ada UPDATE policy.
CREATE POLICY "chat_photos_authenticated_update"
ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'chat-photos'
  AND auth.role() = 'authenticated'
)
WITH CHECK (
  bucket_id = 'chat-photos'
  AND auth.role() = 'authenticated'
);
