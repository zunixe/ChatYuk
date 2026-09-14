-- Lapis 3: invariant AI dummy (kill-switch, kontrak callback, fungsi kunci).
begin;
select supabase_tests.begin_tests();

-- ── Fungsi kunci masih ada ──
select supabase_tests.check('ai_reply_enqueue() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_reply_enqueue'));
select supabase_tests.check('ai_reply_post() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_reply_post'));
select supabase_tests.check('ai_reply_claim_recovery() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='ai_reply_claim_recovery'));

-- ── Trigger enqueue terpasang di private_messages ──
select supabase_tests.check('trigger ai_reply_enqueue terpasang',
  exists(select 1 from pg_trigger t
         join pg_class c on c.oid=t.tgrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='private_messages'
           and not t.tgisinternal and t.tgname ilike '%ai_reply%'));

-- ── Kill switch global ada & bisa dibaca ──
select supabase_tests.check('app_settings.ai_global_enabled ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='app_settings'
           and column_name='ai_global_enabled'));

-- ── Kolom kontrak callback (key/value store) ──
select supabase_tests.check('ai_internal_config punya key/value',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='ai_internal_config' and column_name='key')
  and exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='ai_internal_config' and column_name='value'));

-- ── Flag per dummy yang dipakai lintas-fitur tetap ada ──
select supabase_tests.check('dummy_accounts.ai_no_sleep ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='dummy_accounts'
           and column_name='ai_no_sleep'));
select supabase_tests.check('dummy_accounts.ai_always_online ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='dummy_accounts'
           and column_name='ai_always_online'));
select supabase_tests.check('dummy_accounts.ai_persona ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='dummy_accounts'
           and column_name='ai_persona'));

-- ── Cron kritis terdaftar & aktif ──
select supabase_tests.check('cron ai-presence aktif',
  exists(select 1 from cron.job where jobname='chatyuk-ai-presence' and active));
select supabase_tests.check('cron ai-claim-recovery aktif',
  exists(select 1 from cron.job where jobname='chatyuk-ai-claim-recovery' and active));

select supabase_tests.report() as result;
rollback;
