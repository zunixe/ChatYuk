-- ============================================
-- Bersihkan presence room yang basi (ghost "online" di room)
-- Row room_presence ditinggalkan ketika app di-kill/force-stop
-- tanpa sempat memanggil leaveRoom. Heartbeat client (60 detik)
-- memperbarui joined_at selama room terbuka, jadi row dengan
-- joined_at lama (> threshold) pasti sudah tidak aktif.
-- Dipanggil dari app saat start (fire-and-forget).
-- ============================================

create or replace function public.cleanup_stale_presence(min_age_minutes int default 10)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted int := 0;
begin
  delete from public.room_presence
  where joined_at < now() - make_interval(mins => min_age_minutes);
  get diagnostics deleted = row_count;
  return deleted;
end;
$$;

revoke execute on function public.cleanup_stale_presence(int) from public, anon;
grant execute on function public.cleanup_stale_presence(int) to authenticated, service_role;

-- Bersihkan row basi yang sudah terlanjur ada
delete from public.room_presence
where joined_at < now() - interval '10 minutes';

-- CATATAN: Migration ini sudah dijalankan manual via dashboard SQL editor
-- (2026-08-16) DAN sudah direkam di supabase_migrations.schema_migrations,
-- jadi `supabase db push` akan melewatinya.
--
-- Satu kali pembersihan data manual TIDAK termasuk di file ini:
-- hapus akun test vtest-a (d3b6e0d5-ceab-41a7-a859-f994a2b6d215) dan
-- vtest-b (09f6988e-a20a-4647-91e8-27cfee9cccc4) beserta room_presence,
-- blocks, reports, user_photos, messages, private_messages, coin_ledger,
-- point_events, topup_orders, dummy_accounts, profiles, auth.users.
-- DELETE auth.users cascade ke coin_ledger → blokir trigger append-only
-- dengan `set session_replication_role = 'replica'` (pola yang sama dengan
-- admin_delete_chat di 20260815040000_admin_delete_chat_coinledger_fix.sql).