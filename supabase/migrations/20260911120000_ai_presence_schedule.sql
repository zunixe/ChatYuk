-- ============================================================
-- FITUR: AI mengatur kehadiran dummy (online/idle/offline)
--
-- Permintaan owner:
--   - Ketika AI aktif, AI mengatur kapan dummy online/idle/offline.
--   - Offline → AI TIDAK membalas sama sekali.
--   - Idle → saat AI mau membalas, dummy otomatis jadi online dulu.
--   - Cronjob menyalakan/mematikan sesuai jadwal yang tersimpan.
--   - Jadwal mengikuti kebiasaan jam aktif dummy (dari riwayat chat).
--
-- Implementasi:
--   1. Kolom dummy_accounts.ai_active_hours (jsonb array int jam WIB
--      0-23 yang aktif; '[]' = belum diatur → tick tidak menyentuh).
--   2. admin_ai_autoschedule(p_uid): derive kebiasaan jam dari riwayat
--      private_messages dummy 14 hari terakhir (WIB), simpan, return.
--   3. ai_presence_tick(): set online/offline + jaga last_seen.
--   4. pg_cron: jalankan tick tiap 5 menit.
-- ============================================================

alter table public.dummy_accounts
  add column if not exists ai_active_hours jsonb not null default '[]'::jsonb;

-- Derive kebiasaan jam aktif dari riwayat chat (14 hari, WIB = UTC+7).
-- Jam dianggap "aktif" bila ada >= 2 pesan dummy pada jam tsb; hasil
-- selalu diisi minimal 6 jam supaya dummy tidak mati total.
create or replace function public.admin_ai_autoschedule(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_hours jsonb;
  v_ids int;
begin
  if not exists (select 1 from public.dummy_accounts d where d.uid = p_uid) then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(hr order by hr), '[]'::jsonb)
  into v_hours
  from (
    select extract(hour from (m.created_at + interval '7 hours'))::int as hr
    from public.private_messages m
    where m.sender_id = p_uid
      and m.created_at > now() - interval '14 days'
      and coalesce(m.type, 'text') = 'text'
    group by hr
    having count(*) >= 2
  ) s;

  -- Fallback: kebiasaan kosong/minim → pakai jam aktif generik 8-23.
  if v_hours is null or jsonb_array_length(v_hours) < 6 then
    v_hours := '[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]'::jsonb;
  end if;

  update public.dummy_accounts
     set ai_active_hours = v_hours
   where uid = p_uid;

  return jsonb_build_object('hours', v_hours);
end;
$fn$;

revoke execute on function public.admin_ai_autoschedule(uuid) from public, anon;
grant execute on function public.admin_ai_autoschedule(uuid) to authenticated, service_role;

-- Tick presence: dipanggil cronjob tiap 5 menit.
create or replace function public.ai_presence_tick()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  d record;
  v_hour int;
  v_active bool;
begin
  v_hour := extract(hour from (now() + interval '7 hours'))::int;

  for d in
    select da.uid, da.ai_active_hours, p.status as cur_status
    from public.dummy_accounts da
    join public.profiles p on p.id = da.uid
    where da.ai_enabled = true
  loop
    -- Jadwal belum diatur → jangan sentuh presence (mode manual).
    if d.ai_active_hours is null or
       jsonb_array_length(d.ai_active_hours) = 0 then
      continue;
    end if;

    v_active := (v_hour::int = any(
      select (x::int)
      from jsonb_array_elements_text(d.ai_active_hours) as x
    ));

    if v_active and d.cur_status = 'offline' then
      update public.profiles
         set status = 'online', last_seen = now()
       where id = d.uid;
    elsif v_active and d.cur_status in ('online', 'idle') then
      -- Jaga last_seen segar supaya tetap muncul di daftar online (window 30m).
      update public.profiles set last_seen = now() where id = d.uid;
    elsif not v_active and d.cur_status <> 'offline' then
      update public.profiles set status = 'offline' where id = d.uid;
    end if;
  end loop;
end;
$fn$;

revoke execute on function public.ai_presence_tick() from public, anon;
grant execute on function public.ai_presence_tick() to service_role;

-- Cronjob: tiap 5 menit (idempotent).
select cron.unschedule('chatyuk-ai-presence')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-presence');

select cron.schedule(
  'chatyuk-ai-presence',
  '*/5 * * * *',
  $$select public.ai_presence_tick();$$
);
