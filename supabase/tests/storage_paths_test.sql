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

select supabase_tests.report() as result;
rollback;
