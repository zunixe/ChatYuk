-- Voice Room Global: stage audio (max 6 mic nyala, pendengar unlimited).
--
-- DESAIN (disetujui user): audio-only, mic default mati, tap untuk naik
-- stage & bicara; admin/owner bisa mute paksa; keluar room = turun stage.
-- Mesh WebRTC (pola room_broadcast_service.dart), signaling via tabel.
--
-- 1) room_voice_signals: offer/answer/candidate/join/bye/mute per room.
-- 2) room_voice_speakers: siapa di stage + heartbeat (PK room_id+uid).
-- 3) RPC: join (enforce max 6) / heartbeat / leave / mute (owner/app-admin)
--    / sweep (watchdog + purge).
-- 4) Cron tiap menit: sweep speakers basi (>45 dtk) + signals >2 jam.
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
--   Lihat supabase/migrations/APPLIED_VIA_API.md.

-- ---------- 1) Signaling voice ----------
create table if not exists public.room_voice_signals (
  id         bigint generated always as identity primary key,
  room_id    text not null,
  from_uid   uuid not null,
  to_uid     uuid,                       -- null = broadcast ke semua
  type       text not null,              -- v_join|v_offer|v_answer|v_cand|v_bye|v_mute
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists room_voice_signals_fetch_idx
  on public.room_voice_signals (room_id, id);

alter table public.room_voice_signals enable row level security;

-- Global room terbuka (is_private=false): siapa pun boleh baca/tulis sinyal.
-- Grup private: harus member (pola room_signals).
drop policy if exists rvs_insert on public.room_voice_signals; -- SAFE: idempotent re-apply file ini sendiri
create policy rvs_insert on public.room_voice_signals -- SAFE: sinyal voice ephemeral per-room; tulis hanya from_uid sendiri + room global/member
  for insert with check (
    from_uid = auth.uid()
    and (
      exists (select 1 from public.rooms r
               where r.id = room_voice_signals.room_id
                 and coalesce(r.is_private, false) = false)
      or exists (select 1 from public.room_members m
                  where m.room_id = room_voice_signals.room_id
                    and m.user_id = auth.uid())
    )
  );
drop policy if exists rvs_select on public.room_voice_signals; -- SAFE: idempotent re-apply file ini sendiri
create policy rvs_select on public.room_voice_signals -- SAFE: baca sinyal voice hanya room global/member (tanpa ini client tak terima offer)
  for select using (
    exists (select 1 from public.rooms r
             where r.id = room_voice_signals.room_id
               and coalesce(r.is_private, false) = false)
    or exists (select 1 from public.room_members m
                where m.room_id = room_voice_signals.room_id
                  and m.user_id = auth.uid())
  );

alter publication supabase_realtime add table public.room_voice_signals;

-- ---------- 2) Stage speakers ----------
create table if not exists public.room_voice_speakers (
  room_id    text not null,
  uid        uuid not null,
  updated_at timestamptz not null default now(),
  primary key (room_id, uid)
);

create index if not exists room_voice_speakers_room_idx
  on public.room_voice_speakers (room_id, updated_at desc);

alter table public.room_voice_speakers enable row level security;

-- Baca: global terbuka / member. Tulis HANYA via RPC (tanpa policy
-- insert/update/delete = deny) supaya max-6 & otorisasi mute terjamin.
drop policy if exists rvsp_select on public.room_voice_speakers; -- SAFE: idempotent re-apply file ini sendiri
create policy rvsp_select on public.room_voice_speakers -- SAFE: daftar stage publik per-room (tulis tetap via RPC saja)
  for select using (
    exists (select 1 from public.rooms r
             where r.id = room_voice_speakers.room_id
               and coalesce(r.is_private, false) = false)
    or exists (select 1 from public.room_members m
                where m.room_id = room_voice_speakers.room_id
                  and m.user_id = auth.uid())
  );

alter publication supabase_realtime add table public.room_voice_speakers;

-- ---------- 3) RPC ----------
-- Naik stage: tolak bila 6 mic sudah aktif (hitung yang heartbeat <45 dtk).
create or replace function public.room_voice_join(p_room_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  me uuid := auth.uid();
  v_count int;
  v_allowed boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select (
    exists (select 1 from public.rooms r
             where r.id = p_room_id
               and coalesce(r.is_private, false) = false)
    or exists (select 1 from public.room_members m
                where m.room_id = p_room_id and m.user_id = me)
  ) into v_allowed;
  if not coalesce(v_allowed, false) then
    raise exception 'Not a member';
  end if;

  select count(*) into v_count
    from public.room_voice_speakers s
   where s.room_id = p_room_id
     and s.updated_at > now() - interval '45 seconds'
     and s.uid <> me;
  if v_count >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'stage_full');
  end if;

  insert into public.room_voice_speakers (room_id, uid, updated_at)
  values (p_room_id, me, now())
  on conflict (room_id, uid)
  do update set updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'speakers', coalesce((
      select jsonb_agg(s.uid order by s.updated_at)
        from public.room_voice_speakers s
       where s.room_id = p_room_id
         and s.updated_at > now() - interval '45 seconds'
    ), '[]'::jsonb)
  );
end;
$fn$;

-- Heartbeat stage (dipanggil tiap ~15 dtk selama mic nyala).
create or replace function public.room_voice_heartbeat(p_room_id text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if auth.uid() is null then return; end if;
  update public.room_voice_speakers
     set updated_at = now()
   where room_id = p_room_id and uid = auth.uid();
end;
$fn$;

-- Turun stage sendiri.
create or replace function public.room_voice_leave(p_room_id text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if auth.uid() is null then return; end if;
  delete from public.room_voice_speakers
   where room_id = p_room_id and uid = auth.uid();
end;
$fn$;

-- Mute paksa: owner room ATAU app admin. Menghapus dari stage + menaruh
-- sinyal v_mute agar client target langsung mematikan mic-nya.
create or replace function public.room_voice_mute(p_room_id text, p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  me uuid := auth.uid();
  v_can boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_target is null or p_target = me then
    return jsonb_build_object('ok', false, 'reason', 'bad_target');
  end if;

  select (
    exists (select 1 from public.rooms r
             where r.id = p_room_id and r.owner_id = me)
    or coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
    or auth.role() = 'service_role'
  ) into v_can;
  if not coalesce(v_can, false) then
    raise exception 'Unauthorized';
  end if;

  delete from public.room_voice_speakers
   where room_id = p_room_id and uid = p_target;

  insert into public.room_voice_signals (room_id, from_uid, to_uid, type, payload)
  values (p_room_id, me, p_target, 'v_mute',
          jsonb_build_object('at', now()));

  return jsonb_build_object('ok', true);
end;
$fn$;

-- Watchdog: buang speaker basi (>45 dtk, mis. app crash) + sinyal >2 jam.
create or replace function public.room_voice_sweep()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_n int := 0;
  v_m int;
begin
  delete from public.room_voice_speakers
   where updated_at < now() - interval '45 seconds';
  get diagnostics v_n = row_count;

  delete from public.room_voice_signals
   where created_at < now() - interval '2 hours';
  get diagnostics v_m = row_count;

  return v_n + v_m;
end;
$fn$;

-- ---------- 4) Grant ----------
revoke execute on function public.room_voice_join(text) from public, anon;
revoke execute on function public.room_voice_heartbeat(text) from public, anon;
revoke execute on function public.room_voice_leave(text) from public, anon;
revoke execute on function public.room_voice_mute(text, uuid) from public, anon;
grant execute on function public.room_voice_join(text) to authenticated, service_role;
grant execute on function public.room_voice_heartbeat(text) to authenticated, service_role;
grant execute on function public.room_voice_leave(text) to authenticated, service_role;
grant execute on function public.room_voice_mute(text, uuid) to authenticated, service_role;
revoke execute on function public.room_voice_sweep() from public, anon;

-- ---------- 5) Cron watchdog tiap menit ----------
select cron.schedule('sweep_room_voice', '* * * * *',
  $$select public.room_voice_sweep()$$);
