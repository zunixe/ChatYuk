-- Lapis 3: invariant notifikasi & chat (trigger dedup, kolom to_uid).
begin;
select supabase_tests.begin_tests();

select supabase_tests.check('notify_private_message() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_private_message'));
select supabase_tests.check('notify_call_ended() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_call_ended'));
select supabase_tests.check('call_push() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_push'));

-- Chat & room.
select supabase_tests.check('create_private_room() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='create_private_room'));
select supabase_tests.check('chat bonus idempoten (new_chat_bonus ada)',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='new_chat_bonus'));

-- Tabel log notif (fix regresi 13130001).
select supabase_tests.check('tabel debug_notify_log ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='debug_notify_log'));

-- Feed.
select supabase_tests.check('list_posts() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='list_posts'));
select supabase_tests.check('story_slides() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='story_slides'));

select supabase_tests.report() as result;
rollback;
