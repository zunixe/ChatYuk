-- Lapis 3: invariant OUTBOX + konsistensi snapshot profil.
--
-- Tujuan: mengunci agar (2026-09-27) tidak diregresikan:
--   1. Trigger notif terpindah-pindah memakai `insert into outbox`, BUKAN
--      `net.http_post` sinkron (bikin transaksi tulis pesan menunggu HTTP).
--   2. Token notif diambil dari `user_devices` (helper user_fcm_tokens),
--      BUKAN `profiles.fcm_token` (legacy, sudah dikosongkan).
--   3. Snapshot `profiles.nickname` konsisten di tabel yang menyimpan
--      `author_name`/`nickname_snapshot` (mencegah drift nama lama).
--
-- Semua transaksional (BEGIN/ROLLBACK) → data produksi tak tersentuh.
begin;
select supabase_tests.begin_tests();

-- ── 1. Tabel & helper outbox ────────────────────────────────────────────────
select supabase_tests.check('tabel public.outbox ada',
  exists(select 1 from information_schema.tables
         where table_schema='public' and table_name='outbox'));
select supabase_tests.check('helper user_fcm_tokens(uuid) ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='user_fcm_tokens'));
select supabase_tests.check('index idx_outbox_unsent ada',
  exists(select 1 from pg_indexes
         where schemaname='public' and indexname='idx_outbox_unsent'));
select supabase_tests.check('cron chatyuk-outbox-worker terjadwal',
  exists(select 1 from cron.job where jobname='chatyuk-outbox-worker'));

-- ── 2. Trigger notif pakai OUTBOX (bukan http_post sinkron) ─────────────────
select supabase_tests.check('notify_private_message pakai outbox',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_private_message'
           and p.prosrc like '%outbox%'));
select supabase_tests.check('notify_private_message TIDAK http_post sinkron',
  not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_private_message'
           and p.prosrc like '%http_post%'));
select supabase_tests.check('notify_call_ended pakai outbox',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_call_ended'
           and p.prosrc like '%outbox%'));
select supabase_tests.check('call_push (semua overload) pakai outbox',
  not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_push'
           and p.prosrc not like '%outbox%'));
select supabase_tests.check('notify_mention_room pakai outbox',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_mention_room'
           and p.prosrc like '%outbox%'));

-- ── 3. Token notif dari user_devices (helper), bukan profiles.fcm_token ─────
select supabase_tests.check('notify_private_message pakai user_fcm_tokens',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='notify_private_message'
           and p.prosrc like '%user_fcm_tokens%'));
select supabase_tests.check('call_push pakai user_fcm_tokens',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='call_push'
           and p.prosrc like '%user_fcm_tokens%'));
select supabase_tests.check('helper user_fcm_tokens pakai user_devices',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='user_fcm_tokens'
           and p.prosrc like '%user_devices%'));

-- ── 4. Konsistensi SNAPSHOT profil (anti-drift) ─────────────────────────────
-- posts.author_name harus == profiles.nickname penulisnya (trigger sync aktif).
select supabase_tests.check('trigger trg_sync_profile_names ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public'
           and p.proname in ('sync_profile_names','trg_sync_profile_names')));
select supabase_tests.check('posts.author_name sinkron dgn profiles.nickname',
  not exists(
    select 1 from public.posts po
    join public.profiles pr on pr.id = po.author_id
    where coalesce(po.author_name,'') <> coalesce(pr.nickname,'')));

-- ── 5. Index penting untuk skala (jangan sampai hilang) ─────────────────────
select supabase_tests.check('index urutan list chat ada',
  exists(select 1 from pg_indexes
         where schemaname='public'
           and indexname='idx_private_chats_last_message_at_desc'));
select supabase_tests.check('gin participants private_chats ada',
  exists(select 1 from pg_indexes
         where schemaname='public'
           and indexname='idx_private_chats_participants_gin'));

select supabase_tests.report() as result;
rollback;
