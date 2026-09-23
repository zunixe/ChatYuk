-- Lapis 3: invariant STORY — penonton (admin bebas) + pariti mark_seen.
--
-- Mengunci migrasi 20260923120000:
--   1) `story_viewers` mengizinkan author ATAU admin (is_admin_request),
--      supaya tombol penonton admin di viewer tidak lagi gagal diam-diam.
--   2) `mark_story_seen` dan `mark_story_seen_bulk` punya daftar visibility
--      yang SAMA ('everyone'/'followers'/'friends'/'registered') + cek
--      blokir + privacy_can_view — mencegah penonton "hilang" dari daftar
--      untuk sebagian visibility.
begin;
select supabase_tests.begin_tests();

-- ── Fungsi kunci ada ──
select supabase_tests.check('story_viewers() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='story_viewers'));
select supabase_tests.check('mark_story_seen() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='mark_story_seen'));
select supabase_tests.check('mark_story_seen_bulk() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='mark_story_seen_bulk'));
select supabase_tests.check('is_admin_request() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='is_admin_request'));

-- ── story_viewers: guard admin ──
select supabase_tests.check('story_viewers: guard pakai is_admin_request',
  (select pg_get_functiondef(p.oid) like '%is_admin_request%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='story_viewers'));

-- ── mark_story_seen: pariti visibility ──
select supabase_tests.check('mark_story_seen: ada cabang followers',
  (select pg_get_functiondef(p.oid) like '%followers%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen'));
select supabase_tests.check('mark_story_seen: ada cabang registered',
  (select pg_get_functiondef(p.oid) like '%registered%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen'));
select supabase_tests.check('mark_story_seen: ada cek blokir',
  (select pg_get_functiondef(p.oid) like '%blocks%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen'));
select supabase_tests.check('mark_story_seen: hormati privacy_can_view',
  (select pg_get_functiondef(p.oid) like '%privacy_can_view%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen'));

-- ── mark_story_seen_bulk: pariti visibility ──
select supabase_tests.check('mark_story_seen_bulk: ada cabang followers',
  (select pg_get_functiondef(p.oid) like '%followers%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen_bulk'));
select supabase_tests.check('mark_story_seen_bulk: ada cabang registered',
  (select pg_get_functiondef(p.oid) like '%registered%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen_bulk'));
select supabase_tests.check('mark_story_seen_bulk: hormati privacy_can_view',
  (select pg_get_functiondef(p.oid) like '%privacy_can_view%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mark_story_seen_bulk'));

-- ── Tabel + PK + index penonton ──
select supabase_tests.check('tabel story_views ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='story_views'));
select supabase_tests.check('story_views PK (story_id, viewer_id)',
  exists(select 1 from pg_index i
         join pg_class c on c.oid=i.indrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='story_views'
           and i.indisprimary
           and (select count(*) from unnest(i.indkey) k) = 2));
select supabase_tests.check('index idx_story_views_story_viewer ada',
  exists(select 1 from pg_indexes
         where schemaname='public' and indexname='idx_story_views_story_viewer'));

-- ── Route client yang bergantung sudah ada (regression story tray/slides) ──
select supabase_tests.check('story_tray() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='story_tray'));
select supabase_tests.check('story_slides() FROZEN tetap ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='story_slides'));

select supabase_tests.report() as result;
rollback;
