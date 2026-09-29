-- ============================================================
-- STABILITAS: kurangi beban tulis `profiles` (penyebab stall admin 2026-09-29).
--
-- BUKTI (pg_stat_statements + log):
--   - `UPDATE profiles SET last_seen/status`: 302 panggilan, total 71 s,
--     MEAN 235 ms, MAX 7,7 s (untuk tabel 298 baris — tidak wajar).
--   - `notify_online_fanout` (AFTER UPDATE) melakukan `UPDATE profiles` NESTED
--     di dalam trigger → setiap transisi status menulis DUA kali + memicu
--     ULANG seluruh 9 trigger profiles → WAL berlipat.
--   - 14 akun DUMMY ikut fanout (`net.http_post` ke edge `fanout`) dan
--     `notify_contact_online` menulis outbox untuk 94 chat berisi dummy →
--     spam push + beban tulis tiap `ai_presence_tick` (tiap 5 menit).
--   - `cron.job_run_details` membengkak 44 MB (137k baris, tumbuh tanpa batas).
--   Akibat lanjutan: WAL/checkpoint berat (32-41 s), realtime.list_changes 14 s,
--   statement_timeout → panel admin "mati".
--
-- PERBAIKAN:
--   1. `notify_online_fanout` → BEFORE UPDATE: set `new.last_online_notified_at`
--      LANGSUNG (hilangkan UPDATE nested). Tetap kirim net.http_post.
--   2. Kedua trigger online MENGECUALIKAN akun dummy (bot: presence-nya diatur
--      `ai_presence_tick`; notifikasi "X online" untuk bot hanyalah beban/spam).
--   3. `housekeeping_tick` memangkas `cron.job_run_details` > 7 hari.
--
-- Menyentuh fungsi FROZEN? TIDAK (notify_online_fanout / notify_contact_online
-- / housekeeping_tick tak ada di scripts/frozen_functions.txt).
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md).
-- ============================================================

-- ── 1. notify_online_fanout: BEFORE UPDATE + skip dummy + tanpa nested UPDATE ──
create or replace function public.notify_online_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status = 'online' and coalesce(old.status, 'offline') <> 'online' then
    -- Dummy = bot; presence dikelola ai_presence_tick. Fanout ke bot hanya
    -- memicu http_post + outbox tiap 5 menit (beban, bukan value).
    if exists (select 1 from public.dummy_accounts d where d.uid = new.id) then
      return new;
    end if;
    if new.last_online_notified_at is null
       or now() - new.last_online_notified_at > interval '10 minutes' then
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
        headers := jsonb_build_object('Content-Type','application/json'),
        body := jsonb_build_object('type','online','id', new.id::text)
      );
      -- BEFORE trigger: cukup set kolomnya. Dulu ada `UPDATE profiles ...`
      -- nested di AFTER trigger → menulis 2× + memicu ulang semua trigger.
      new.last_online_notified_at := now();
    end if;
  end if;
  return new;
end;
$function$;

-- Pindahkan trigger dari AFTER ke BEFORE (agar `new.*` bisa di-set).
drop trigger if exists profiles_online_fanout_trigger on public.profiles;
create trigger profiles_online_fanout_trigger
  before update of status on public.profiles
  for each row execute function public.notify_online_fanout();

-- ── 2. notify_contact_online: kecualikan dummy ────────────────────────────────
create or replace function public.notify_contact_online()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  contact_id uuid;
  contact_chat text;
  t text;
begin
  if new.status <> 'online' or old.status = 'online' then return new; end if;
  -- Dummy: bot tidak perlu memberi tahu kontak bahwa ia "online".
  if exists (select 1 from public.dummy_accounts d where d.uid = new.id) then
    return new;
  end if;
  for contact_id, contact_chat in
    select distinct u as uid, pc.chat_id
      from public.private_chats pc
      cross join lateral unnest(pc.participants) as u
     where new.id = any (pc.participants) and u <> new.id
  loop
    for t in select public.user_fcm_tokens(contact_id) loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
        'endpoint','send-push',
        'token', t,
        'title', coalesce(new.nickname,'Anon'),
        'body', 'is online',
        'data', jsonb_build_object(
          'type','online','chatId',contact_chat,
          'otherUid',new.id,'otherName',coalesce(new.nickname,'Anon')
        )
      ));
    end loop;
  end loop;
  return new;
exception when others then return new;
end;
$function$;

-- ── 3. housekeeping_tick: retensi cron.job_run_details (> 7 hari) ─────────────
create or replace function public.housekeeping_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_idle   int := -1;
  v_voice  int := -1;
  v_cron   int := 0;
begin
  begin
    v_idle := public.presence_idle_tick();
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
  -- Tabel riwayat cron tumbuh tanpa batas (44 MB / 137k baris) → pangkas.
  begin
    delete from cron.job_run_details
     where start_time < now() - interval '7 days';
    get diagnostics v_cron = row_count;
  exception when others then null;
  end;
  return jsonb_build_object(
    'presence_idle', v_idle, 'voice_sweep', v_voice, 'cron_purged', v_cron
  );
end;
$function$;

-- Verifikasi:
--   select proname, (prosrc ilike '%dummy_accounts%') skip_dummy,
--          (prosrc ilike '%new.last_online_notified_at%') no_nested
--     from pg_proc where proname in ('notify_online_fanout','notify_contact_online');
--   select tgname, tgtype from pg_trigger where tgname='profiles_online_fanout_trigger';
--     → BEFORE UPDATE (tgtype & 2 = 1 → BEFORE).
