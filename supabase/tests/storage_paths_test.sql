-- pgTAP: kontrak penyimpanan gambar — DB simpan PATH storage,
-- bukan base64. Satu bucket `chat-photos`, beda prefix per jenis:
-- story/ slide, posts/ timeline, chat/ pesan, voice/ audio,
-- avatars/ profil, gallery/ galeri.
-- Kolom diperiksa level skema (bukan isi data) supaya row legacy
-- base64 (sebelum backfill) tidak membuat test merah.
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('stories.image_path ada',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'stories'
      and column_name = 'image_path'
  ));

select supabase_tests.check('user_photos.photo ada',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_photos'
      and column_name = 'photo'
  ));

select supabase_tests.check('posts.image_path ada',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'posts'
      and column_name = 'image_path'
  ));

select supabase_tests.check('private_messages punya kolom gambar (image_path)',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'private_messages'
      and column_name = 'image_path'
  ));

select supabase_tests.check('messages punya kolom gambar (image_path)',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'messages'
      and column_name = 'image_path'
  ));

-- REGRESI 2026-10-05: upload foto ROOM gagal — policy storage menolak
-- `chat/room_<roomId>/...` (dulu hanya cek private_chats). Fungsi owner_ok
-- harus menangani segmen 'room_'.
select supabase_tests.check('storage_object_owner_ok tangani path room',
  (select pg_get_functiondef(p.oid) like '%room\_%'
     and pg_get_functiondef(p.oid) like '%room_members%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='storage_object_owner_ok'
   limit 1));

select supabase_tests.report() as result;
rollback;
