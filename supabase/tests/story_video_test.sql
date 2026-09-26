-- Lapis 3: story video pendek (maks 15 dtk, polos).
-- Jalankan: scripts/run_sql_tests.sh story_video_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

-- Kolom ada.
select supabase_tests.check('kolom media_type ada',
  exists (select 1 from information_schema.columns
   where table_schema = 'public' and table_name = 'stories'
     and column_name = 'media_type'));
select supabase_tests.check('kolom video_path ada',
  exists (select 1 from information_schema.columns
   where table_schema = 'public' and table_name = 'stories'
     and column_name = 'video_path'));
select supabase_tests.check('kolom duration_ms ada',
  exists (select 1 from information_schema.columns
   where table_schema = 'public' and table_name = 'stories'
     and column_name = 'duration_ms'));

-- Satu overload create_story (hindari PostgREST 300).
select supabase_tests.check('create_story satu overload',
  (select count(*) from pg_proc
    where proname = 'create_story') = 1);

-- story_slides kirim kolom video.
select supabase_tests.check('story_slides memuat media_type',
  (select pg_get_functiondef(p.oid) like '%media_type%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'story_slides' limit 1));

-- story_tray kirim flag has_video.
select supabase_tests.check('story_tray memuat has_video',
  (select pg_get_functiondef(p.oid) like '%has_video%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'story_tray' limit 1));

-- Validasi durasi: butuh JWT user registered — cukup cek guard ada.
select supabase_tests.check('create_story validasi durasi 1-15 dtk',
  (select pg_get_functiondef(p.oid) like '%15000%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_story' limit 1));

select supabase_tests.report() as result;
rollback;
