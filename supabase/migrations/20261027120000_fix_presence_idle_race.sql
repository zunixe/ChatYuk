-- ============================================================
-- FIX: user AKTIF hilang dari daftar Online (status jatuh ke idle/offline).
--
-- TEMUAN LIVE (2026-10-26, kasus "pornsex"):
--   User aktif ~29 menit lalu, status DB = 'offline' → tidak muncul di
--   `get_online_users` (butuh status online/idle DAN last_seen <= 30 mnt).
--   `presence_visibility` = 'everyone', bukan ghost, bukan invisible admin.
--   Jadi bukan privasi — murni status yang salah.
--
-- AKAR MASALAH (RACE):
--   * Klien mengirim heartbeat tiap `heartbeatInterval = 240s` (4 menit).
--   * `presence_idle_tick(p_idle_after default interval '4 minutes')`
--     menurunkan 'online' → 'idle' bila `last_seen < now() - 4 menit`.
--   * AMBANG IDLE == INTERVAL HEARTBEAT. Setiap jitter jaringan / timer drift
--     / app sempat background membuat cron MENDAHULUI heartbeat → user
--     sedang aktif ikut diturunkan ke 'idle'.
--   * Setelah 30 menit tanpa heartbeat (app benar-benar ditutup OS),
--     `presence_stale_offline(30)` memindahkan ke 'offline' — dan status
--     'offline' TIDAK pernah kembali sendiri tanpa heartbeat, sehingga user
--     yang kembali membuka app sempat "tak terlihat" sampai heartbeat
--     berikutnya (hingga 4 menit).
--
-- PERBAIKAN:
--   1) Ambang idle 4 mnt → **10 mnt** (2.5x heartbeat 4 mnt): beri ruang
--      2-3 heartbeat yang terlewat sebelum dianggap idle, sehingga user
--      yang benar-benar memakai app tidak pernah jatuh ke idle.
--      Batas atas tetap 30 mnt (jendela tampil) — tidak menyentuh user yang
--      sudah "offline efektif".
--   2) Idle TIDAK lagi menyentuh `last_seen` (biarkan heartbeat yang
--      mengurus). Status saja yang turun.
--   3) Semua pemanggil housekeeping_tick memakai ambang baru.
--
-- TIDAK mengubah: get_online_users, presence_for, RPC lain, atau semantik
-- privacy. Hanya ambang waktu idle.
--
-- CARA APPLY: Management API / SQL editor (CI `db push` di Mac ini HANG).
-- ROLLBACK: re-apply `20260914060001_presence_idle_tick.sql` (default 4 mnt).
-- ============================================================

-- ── 1) presence_idle_tick: ambang default 10 menit ─────────────────────────
create or replace function public.presence_idle_tick(
  p_idle_after interval default interval '10 minutes'
)
returns int
language plpgsql
security definer
set search_path to public
as $fn$
declare
  v_n int := 0;
begin
  -- Hanya 'online' → 'idle'. JANGAN sentuh last_seen: nilai itu milik
  -- heartbeat (mencerminkan aktivitas nyata), bukan milik tick.
  -- Batas atas 30 mnt = jendela tampil get_online_users, supaya user yang
  -- sudah "offline efektif" tidak ikut diubah.
  -- Dummy dikecualikan (presence diatur ai_presence_tick / admin panel).
  update public.profiles p
     set status = 'idle'
   where p.status = 'online'
     and p.last_seen is not null
     and p.last_seen < now() - p_idle_after
     and p.last_seen >= now() - interval '30 minutes'
     and not exists (
       select 1 from public.dummy_accounts d where d.uid = p.id
     );
  get diagnostics v_n = row_count;
  return v_n;
exception when others then
  return 0;
end;
$fn$;

revoke execute on function public.presence_idle_tick(interval) from public, anon;
grant execute on function public.presence_idle_tick(interval) to authenticated, service_role;

-- ── 2) housekeeping_tick: pakai ambang 10 menit secara eksplisit ───────────
create or replace function public.housekeeping_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_idle   int := -1;
  v_voice  int := -1;
  v_stale  int := -1;
  v_cron   int := 0;
begin
  begin
    -- 10 mnt = 2.5x heartbeat klien (4 mnt). Lihat header migrasi ini.
    v_idle := public.presence_idle_tick(interval '10 minutes');
  exception when others then null;
  end;
  begin
    v_stale := public.presence_stale_offline(30);
  exception when others then null;
  end;
  begin
    v_voice := public.room_voice_sweep();
  exception when others then null;
  end;
  begin
    delete from public.room_signals
     where created_at < now() - interval '2 minutes';
  exception when others then null;
  end;
  begin
    delete from public.room_broadcasters
     where started_at < now() - interval '2 minutes';
    update public.rooms r
       set live_uid = null, live_started_at = null
     where r.live_uid is not null
       and not exists (
         select 1 from public.room_broadcasters rb
         where rb.room_id = r.id and rb.user_id = r.live_uid
       );
  exception when others then null;
  end;
  begin
    delete from cron.job_run_details
     where start_time < now() - interval '7 days';
    get diagnostics v_cron = row_count;
  exception when others then null;
  end;
  return jsonb_build_object(
    'presence_idle', v_idle, 'presence_stale_offline', v_stale,
    'voice_sweep', v_voice, 'cron_purged', v_cron
  );
end;
$function$;
