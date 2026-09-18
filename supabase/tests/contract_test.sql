-- Lapis 3: kontrak Edge ↔ DB ↔ App (tripwire sinkron dengan
-- supabase/functions/_shared/edge-contract.ts). Kalau RPC/kolom di sini
-- hilang, Edge fanout/send-push + PointsProvider ikut rusak.
begin;
select supabase_tests.begin_tests();

-- Wallet (dipakai PointsProvider.getWallet: bonus/earned/total).
select supabase_tests.check('RPC get_wallet ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='get_wallet'));
select supabase_tests.check('tabel coin_ledger ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='coin_ledger'));
select supabase_tests.check('profiles.points ada (cache total ledger)',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='profiles'
           and column_name='points'));

-- Chat forward (kontrak bubble + forward picker).
select supabase_tests.check('private_messages.is_forwarded ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='private_messages'
           and column_name='is_forwarded'));

-- AI reply pipeline (trigger enqueue → claim → recovery).
select supabase_tests.check('ai_reply_post() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_reply_post'));
select supabase_tests.check('ai_reply_claim_recovery() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_reply_claim_recovery'));

-- Presence tick (kontrak daftar online).
select supabase_tests.check('ai_presence_tick() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_presence_tick'));
select supabase_tests.check('get_online_users() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='get_online_users'));

select supabase_tests.report() as result;
rollback;
