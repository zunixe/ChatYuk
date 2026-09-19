-- Lapis 3: invariant fitur mention `@` (20260921120000_mentions.sql).
-- Melindungi kolom mentions + trigger notifikasi mention room dari regresi.
begin;
select supabase_tests.begin_tests();

-- ── Kolom penyimpanan mention ──
select supabase_tests.check('kolom messages.mentions ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='messages'
           and column_name='mentions' and data_type='jsonb'));
select supabase_tests.check('kolom private_messages.mentions ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='private_messages'
           and column_name='mentions' and data_type='jsonb'));
select supabase_tests.check('default mentions = []',
  (select column_default from information_schema.columns
    where table_schema='public' and table_name='messages'
      and column_name='mentions') like '%[]%');

-- ── Trigger notifikasi mention room ──
select supabase_tests.check('fungsi notify_mention_room() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_mention_room'));
select supabase_tests.check('trigger notify_mention_room_trg terpasang di messages',
  exists(select 1 from pg_trigger t
         join pg_class c on c.oid = t.tgrelid
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname='public' and c.relname='messages'
           and t.tgname='notify_mention_room_trg' and not t.tgisinternal));
select supabase_tests.check('notify_mention_room kirim type=mention + toUid',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_mention_room'
           and pg_get_functiondef(p.oid) like '%''mention''%'
           and pg_get_functiondef(p.oid) like '%toUid%'));

select supabase_tests.report() as result;
rollback;
