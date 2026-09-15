-- ============================================================
-- ChatYuk: RLS STORAGE — ownership check (fix IDOR) + limit upload
-- ============================================================
-- Latar (review 2026-09-14):
--   Policy lama di bucket `chat-photos` hanya cek
--   `bucket_id = 'chat-photos' AND auth.role() = 'authenticated'`
--   TANPA validasi kepemilikan/path → IDOR: user authenticated mana pun
--   bisa overwrite/delete file user lain (avatar, gallery, voice, story,
--   post) dengan menebak/ menyusun path yang dipakai client.
--
-- Bukti: supabase/migrations/20260813000000_chat_photos_storage.sql:17-26
--        supabase/migrations/20260829050000_storage_update_policy.sql:5-15
--
-- Perbaikan:
--   1) Helper public.storage_object_owner_ok(name) — OWNER-OR-ADMIN.
--   2) Ganti 4 policy (select/insert/update/delete) bucket chat-photos:
--        - SELECT : tetap public read (bucket public, path berisi UUID).
--        - INSERT/UPDATE/DELETE : wajib owner sesuai PATH atau admin.
--   3) Trigger BEFORE INSERT/UPDATE on storage.objects (bucket chat-photos):
--        - whitelist content_type (jpeg/png/webp/m4a/mp3)
--        - batas ukuran 8 MB (enforcement server-side, bukan cuma client).
--
-- Layout path aktual (lib/services/storage_photo_service.dart):
--   avatars/<uid>.jpg          | avatars/<uid>_<ts>.jpg
--   gallery/<uid>/<ts>.jpg
--   posts/<uid>/<ts>.jpg
--   story/<uid>/<ts>.jpg
--   timeline/...               (legacy, prefix sama)
--   chat/<chatId>/<ts>.jpg     | voice/<chatId>/<ts>.m4a
--
-- Tidak menyentuh fungsi FROZEN apa pun.
-- ============================================================

-- ── 1. Helper: apakah auth.uid() pemilik objek berdasar PATH ──
create or replace function public.storage_object_owner_ok(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'auth', 'storage'
as $function$
declare
  v_uid     text := auth.uid()::text;
  v_parts   text[] := storage.foldername(p_name);
  v_prefix  text := coalesce(v_parts[1], '');
  v_seg     text := coalesce(v_parts[2], '');
  v_base    text;   -- nama file (segmen terakhir)
  v_stem    text;   -- nama file tanpa ekstensi
begin
  -- admin / service_role selalu boleh
  if public.is_admin_request() then
    return true;
  end if;

  if coalesce(v_uid, '') = '' then
    return false;
  end if;

  -- nama file = segmen terakhir path (mis. 'avatars/<uid>_123.jpg').
  v_base := coalesce(nullif(split_part(p_name, '/',
              array_length(string_to_array(p_name, '/'), 1)), ''), '');
  v_stem := split_part(v_base, '.', 1);

  -- avatars/<uid>_<ts>.jpg atau avatars/<uid>.jpg
  -- → uid ada di NAMA FILE (bukan folder), prefix file = uid.
  if v_prefix = 'avatars' then
    return (
      v_stem = v_uid
      or v_stem like v_uid || '\_%'   -- <uid>_<timestamp>
    );
  end if;

  -- gallery|posts|story|timeline/<uid>/<file>
  if v_prefix in ('gallery', 'posts', 'story', 'timeline') then
    return v_seg = v_uid;
  end if;

  -- chat|voice/<chatId>/<file> → harus peserta private_chats
  if v_prefix in ('chat', 'voice') then
    return exists (
      select 1 from public.private_chats pc
      where pc.chat_id = v_seg
        and auth.uid() = any (pc.participants)
    );
  end if;

  -- prefix tidak dikenal → tolak (fail-closed)
  return false;
end;
$function$;

comment on function public.storage_object_owner_ok(text) is
  'Owner-or-admin gate untuk storage.objects bucket chat-photos berdasar path. admin = is_admin_request().';

-- ── 2. Ganti policy bucket chat-photos ──
-- SAFE: policy lama digantikan (tidak ada data/objek di-drop) — alasan:
--   IDOR (authenticated tanpa ownership check).
drop policy if exists "chat_photos_public_read" on storage.objects;
drop policy if exists "chat_photos_authenticated_insert" on storage.objects;
drop policy if exists "chat_photos_authenticated_update" on storage.objects;
drop policy if exists "chat_photos_authenticated_delete" on storage.objects;
drop policy if exists "chat_photos_owner_insert" on storage.objects;
drop policy if exists "chat_photos_owner_update" on storage.objects;
drop policy if exists "chat_photos_owner_delete" on storage.objects;

-- SELECT: tetap public read (bucket public; path berisi UUID/timestamp).
create policy "chat_photos_public_read" on storage.objects
  for select using (bucket_id = 'chat-photos');

-- INSERT: hanya pemilik path (atau admin).
create policy "chat_photos_owner_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-photos'
    and public.storage_object_owner_ok(name)
  );

-- UPDATE: hanya pemilik path, dan hasilnya tetap path milik sendiri.
create policy "chat_photos_owner_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'chat-photos'
    and public.storage_object_owner_ok(name)
  )
  with check (
    bucket_id = 'chat-photos'
    and public.storage_object_owner_ok(name)
  );

-- DELETE: hanya pemilik path (atau admin/moderation).
create policy "chat_photos_owner_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'chat-photos'
    and public.storage_object_owner_ok(name)
  );

-- ── 3. Enforcement limit ukuran & tipe (server-side) ──
-- Client sudah membatasi, tapi bisa dilewati. Trigger ini fail-closed
-- untuk bucket chat-photos saja (bucket lain tidak terpengaruh).
create or replace function public.chat_photos_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'storage'
as $function$
declare
  v_type text := lower(coalesce(new.metadata->>'mimetype', ''));
  v_size bigint := coalesce((new.metadata->>'size')::bigint, 0);
begin
  if new.bucket_id <> 'chat-photos' then
    return new;
  end if;

  -- tipe diizinkan
  if v_type not in (
    'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
    'audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/mpeg', 'audio/mp3'
  ) then
    raise exception 'Tipe file tidak diizinkan: %', v_type
      using errcode = 'check_violation';
  end if;

  -- batas 8 MB
  if v_size > 8 * 1024 * 1024 then
    raise exception 'Ukuran file melebihi batas 8 MB (%).', v_size
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

comment on function public.chat_photos_guard() is
  'Guard BEFORE INSERT/UPDATE storage.objects bucket chat-photos: whitelist tipe + limit 8 MB.';

drop trigger if exists trg_chat_photos_guard on storage.objects;
create trigger trg_chat_photos_guard
  before insert or update on storage.objects
  for each row execute function public.chat_photos_guard();
