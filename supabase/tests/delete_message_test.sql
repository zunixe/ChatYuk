-- pgTAP: soft-delete pesan (is_deleted) + trigger scrub reply.
-- Mengunci insiden 2026-09-23: UPDATE private_messages.is_deleted=true
-- selalu di-rollback karena trigger scrub_reply_snapshot_private
-- membandingkan replied_to_id (text) dengan new.id (bigint) tanpa cast.
-- Transaksional (BEGIN/ROLLBACK), tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- Kolom is_deleted ada di kedua tabel chat.
select supabase_tests.check('private_messages.is_deleted boolean not null default false',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'private_messages'
      and column_name = 'is_deleted' and data_type = 'boolean'
      and is_nullable = 'NO' and column_default = 'false'
  ));

select supabase_tests.check('messages.is_deleted boolean not null default false',
  exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'messages'
      and column_name = 'is_deleted' and data_type = 'boolean'
      and is_nullable = 'NO' and column_default = 'false'
  ));

-- Trigger scrub private terpasang.
select supabase_tests.check('trigger scrub_reply_snapshot_private_trg terpasang',
  exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'private_messages'
      and t.tgname = 'scrub_reply_snapshot_private_trg' and not t.tgisinternal
  ));

-- Fix cast: new.id::text (bukan text = bigint).
select supabase_tests.check('scrub_reply_snapshot_private pakai new.id::text',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'scrub_reply_snapshot_private'
      and pg_get_functiondef(p.oid) like '%new.id::text%'
  ));

select supabase_tests.report() as result;
rollback;
