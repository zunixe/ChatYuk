-- Lapis 3: invariant call & video call (WebRTC signaling).
-- Melindungi: tabel calls/call_signals, kolom heartbeat/notif, index, RPC
-- inti, cron retensi zombie, dan RLS per-peserta.
-- Transaksional (BEGIN/ROLLBACK) via scripts/run_sql_tests.sh — data
-- produksi tidak tersentuh.
begin;
select supabase_tests.begin_tests();

-- ── 1. Tabel & kolom kritis ──
select supabase_tests.check('tabel calls ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='calls'));

select supabase_tests.check('tabel call_signals ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='call_signals'));

-- last_seen_at = heartbeat peserta (dipakai sweep zombie 75 dtk).
select supabase_tests.check('kolom calls.last_seen_at ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='calls'
           and column_name='last_seen_at'));

-- notif_sent_at = idempotensi notif call (1x per call, anti dobel push).
select supabase_tests.check('kolom calls.notif_sent_at ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='calls'
           and column_name='notif_sent_at'));

select supabase_tests.check('kolom call_signals.payload jsonb ada',
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='call_signals'
           and column_name='payload' and data_type='jsonb'));

-- ── 2. Index performa (sweep & realtime filter) ──
select supabase_tests.check('index calls_open_idx ada',
  exists(select 1 from pg_indexes
         where schemaname='public' and indexname='calls_open_idx'));

select supabase_tests.check('index call_signals_call_idx ada',
  exists(select 1 from pg_indexes
         where schemaname='public' and indexname='call_signals_call_idx'));

-- ── 3. RPC inti ──
select supabase_tests.check('call_push() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_push'));

select supabase_tests.check('notify_call_ended() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_call_ended'));

select supabase_tests.check('touch_call() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='touch_call'));

select supabase_tests.check('admin_sweep_calls() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='admin_sweep_calls'));

select supabase_tests.check('is_chatyuk_admin() ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='is_chatyuk_admin'));

-- ── 4. RLS per-peserta (call hanya boleh dilihat caller/callee) ──
select supabase_tests.check('policy calls_select ada',
  exists(select 1 from pg_policies
         where schemaname='public' and tablename='calls'
           and policyname='calls_select'));

select supabase_tests.check('policy calls_insert ada',
  exists(select 1 from pg_policies
         where schemaname='public' and tablename='calls'
           and policyname='calls_insert'));

select supabase_tests.check('RLS aktif di calls',
  (select relrowsecurity from pg_class c
   join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='calls'));

-- ── 5. Cron retensi zombie (dulu hanya jalan saat admin buka panel) ──
select supabase_tests.check('cron chatyuk-call-sweep terdaftar aktif',
  exists(select 1 from cron.job
         where jobname='chatyuk-call-sweep' and active));

select supabase_tests.check('cron chatyuk-call-sweep tiap 5 menit',
  exists(select 1 from cron.job
         where jobname='chatyuk-call-sweep' and schedule='*/5 * * * *'));

-- ── 6. Perilaku dasar: sweep aman dipanggil & mengembalikan integer ──
-- (transaksional; tidak mengubah data permanen)
select supabase_tests.check('admin_sweep_calls() mengembalikan integer >= 0',
  (select public.admin_sweep_calls()) >= 0);

select supabase_tests.report() as result;
rollback;
