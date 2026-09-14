-- ============================================================
-- Idle otomatis untuk user asli (non-dummy)
--
-- MASALAH (temuan live 2026-09-14, user "yusuf"):
-- Client sudah punya timer idle (auth_provider.idleTimeout 3 mnt →
-- goIdle) dan app.dart memanggil goIdle() saat background/detached.
-- TAPI bila OS membunuh proses di background sebelum request sempat
-- terkirim (umum di Android), status DB mentok di 'online' selamanya
-- sampai effectiveStatusOf (client) membuangnya sebagai 'offline'
-- setelah 30 mnt. Efek: user berhenti tampil 'idle' — lompat
-- online → offline. Idle hanya muncul untuk dummy (ai_presence_tick).
--
-- SOLUSI: tick server menurunkan 'online' → 'idle' untuk user ASLI
-- yang last_seen sudah basi > AMBANG tapi belum lewat jendela tampil
-- (30 mnt, konsisten get_online_users + effectiveStatusOf).
-- Dummy DIKECUALIKAN (status dikelola ai_presence_tick / admin).
-- ============================================================

create or replace function public.presence_idle_tick(
  p_idle_after interval default interval '4 minutes'
)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_n int := 0;
begin
  -- Hanya 'online' (bukan idle/offline/invisible). last_seen masih segar
  -- (< p_idle_after) dikecualikan — mereka benar-benar aktif. Batas atas
  -- 30 mnt = jendela tampil daftar online, supaya tidak menyentuh user yang
  -- sudah "offline efektif" di client.
  -- Dummy dikecualikan: presence-nya diatur ai_presence_tick / admin panel.
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

-- Cron tiap menit: jendela idle 4 menit vs tampil 30 menit → aman,
-- tidak akan menendang user yang baru saja aktif tak sengaja.
select cron.unschedule('chatyuk-presence-idle')
where exists (select 1 from cron.job where jobname = 'chatyuk-presence-idle');

select cron.schedule(
  'chatyuk-presence-idle',
  '* * * * *',
  $$select public.presence_idle_tick()$$
);

-- Index bantu agar tick tidak full-scan profiles.
create index if not exists profiles_status_last_seen_idx
  on public.profiles (status, last_seen desc);
