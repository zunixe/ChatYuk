-- ============================================================
-- Fix lanjutan presence: "user online terus" & status basi menumpuk.
--
-- Dua masalah yang ditemukan saat debug "Siti online terus":
--   (a) clamp_last_seen hanya mencegah last_seen MASA DEPAN, tapi baris
--       yang terlanjur di-clamp ke now() (jam HP maju) tetap tampil online
--       ~30 menit. Lebih benar: bila last_seen di masa depan → set offline
--       (status tak dapat dipercaya).
--   (b) presence_idle_tick hanya ubah online→idle untuk last_seen < 30 mnt;
--       TIDAK PERNAH set offline untuk yang lebih basi → status online/idle
--       menumpuk selamanya (568 baris basi ditemukan). get_online_users tetap
--       menyaring saat baca, tapi status DB jadi tidak jujur (admin panel
--       baca status mentah di beberapa tempat).
-- ============================================================

-- (1) clamp_last_seen: last_seen masa depan → clamp + PAKSA offline.
create or replace function public.clamp_last_seen()
returns trigger
language plpgsql
as $$
begin
  if new.last_seen is not null and new.last_seen > now() then
    new.last_seen := now();
    -- last_seen di masa depan = jam HP maju → status tak dapat dipercaya.
    -- Set offline; heartbeat berikutnya dari app akan mengembalikan online
    -- (goOnline set status='online' lagi) bila user benar-benar aktif.
    new.status := 'offline';
  end if;
  return new;
end;
$$;

-- (2) Fungsi offline-kan presence basi (> 30 menit = di luar jendela online).
create or replace function public.presence_stale_offline(p_stale_minutes int default 30)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int := 0;
begin
  update public.profiles p
     set status = 'offline'
   where p.status in ('online', 'idle')
     and (p.last_seen is null
          or p.last_seen < now() - make_interval(mins => greatest(p_stale_minutes, 1)));
  get diagnostics v_n = row_count;
  return v_n;
exception when others then
  return 0;
end;
$$;

revoke execute on function public.presence_stale_offline(int) from public, anon, authenticated;
grant execute on function public.presence_stale_offline(int) to service_role;

-- (3) Panggil dari housekeeping_tick (cron tiap menit) — jaga status jujur.
create or replace function public.housekeeping_tick()
returns jsonb
language plpgsql
as $$
declare
  v_idle   int := -1;
  v_voice  int := -1;
  v_stale  int := -1;
  v_cron   int := 0;
begin
  begin
    v_idle := public.presence_idle_tick();
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
$$;

-- (4) Bersihkan sekali sekarang: offline-kan semua status basi.
select public.presence_stale_offline(30) as stale_offlined;
