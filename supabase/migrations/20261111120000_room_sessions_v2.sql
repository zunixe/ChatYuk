-- ============================================================
-- 20261111120000_room_sessions_v2.sql
-- Room v2 — "Sesi Terjadwal + Host" (docs/ROOM_V2_TASK.md)
--
-- Global room jadi panggung sesi live terjadwal yang di-host manusia:
--   1) profiles.is_host (admin-set) — flag host, bukan role baru
--   2) room_sessions — jadwal sesi per room + KPI (peak_viewers, gifts_total)
--   3) room_session_reminders — opt-in "ingatkan saat mulai"
--   4) RPC: schedule/start/end/next/toggle_reminder/host_mute/tick/sweep
--      + admin_set_host + admin_room_session_stats
--   5) send_room_gift diaktifkan lagi (dimatikan 20261101100200) dengan
--      ekonomi PAID-ONLY terkini (pola send_gift): is_registered, female
--      block, rate limit coin_tx_max_per_hour, yukcoin_spendable +
--      ledger_spend_promo (bonus hanya lewat promo plafon), penerima
--      SELALU bucket earned. Cabang baru: room global + sesi live →
--      penerima = host sesi, gifts_total sesi += koin kotor.
--
-- Anti-fake: peak_viewers dihitung dari room_presence TANPA dummy_accounts.
-- ============================================================

-- ── 1. Data model ───────────────────────────────────────────
alter table public.profiles
  add column if not exists is_host boolean not null default false;

create table if not exists public.room_sessions (
  id          bigint generated always as identity primary key,
  room_id     text not null references public.rooms(id) on delete cascade,
  host_uid    uuid not null references public.profiles(id),
  title       text not null,
  format      text not null default 'bebas',
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  status      text not null default 'scheduled'
              check (status in ('scheduled','live','ended','cancelled')),
  started_at  timestamptz,
  ended_at    timestamptz,
  peak_viewers int not null default 0,
  gifts_total  int not null default 0,
  created_by  uuid not null,
  created_at  timestamptz not null default now()
);
create index if not exists room_sessions_room_idx
  on public.room_sessions (room_id, status, starts_at);
create index if not exists room_sessions_live_idx
  on public.room_sessions (status) where status = 'live';

create table if not exists public.room_session_reminders (
  session_id bigint not null references public.room_sessions(id) on delete cascade,
  user_id    uuid not null,
  created_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

alter table public.room_sessions enable row level security;
alter table public.room_session_reminders enable row level security;

-- SELECT publik (jadwal tampil di explore/lobby); semua write lewat RPC.
drop policy if exists room_sessions_select on public.room_sessions; -- SAFE: idempotent re-apply file ini sendiri (tabel baru, belum ada konsumen lain)
create policy room_sessions_select on public.room_sessions -- SAFE: read-only publik, write hanya RPC security definer (tabel baru)
  for select using (true);

drop policy if exists room_session_reminders_select_own on public.room_session_reminders; -- SAFE: idempotent re-apply file ini sendiri (tabel baru)
create policy room_session_reminders_select_own on public.room_session_reminders -- SAFE: baris reminder hanya boleh dibaca pemiliknya (tabel baru)
  for select using (user_id = auth.uid());

grant select on public.room_sessions to anon, authenticated; -- SAFE: tabel baru (bukan tabel bersama) — grant baca saja, write via RPC
grant select on public.room_session_reminders to authenticated; -- SAFE: tabel baru (bukan tabel bersama) — reminder milik sendiri (RLS), write via RPC

-- ── 2. RPC admin: set flag host ─────────────────────────────
create or replace function public.admin_set_host(p_uid uuid, p_is_host boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  update public.profiles set is_host = coalesce(p_is_host, false) where id = p_uid;
  if not found then raise exception 'User not found'; end if;
  return jsonb_build_object('ok', true, 'is_host', coalesce(p_is_host, false));
end;
$$;

-- ── 3. RPC jadwal sesi ──────────────────────────────────────
create or replace function public.schedule_room_session(
  p_room_id text, p_host_uid uuid, p_title text, p_format text,
  p_starts_at timestamptz, p_ends_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_fmt text := coalesce(nullif(trim(p_format), ''), 'bebas');
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if v_fmt not in ('karaoke','curhat','debat','quiz','werewolf','musik','bebas') then
    raise exception 'Format tidak valid';
  end if;
  if length(trim(coalesce(p_title, ''))) < 3 or length(trim(p_title)) > 80 then
    raise exception 'Judul harus 3-80 karakter';
  end if;
  if p_starts_at is null or p_ends_at is null or p_starts_at >= p_ends_at then
    raise exception 'Jam mulai harus sebelum jam selesai';
  end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'Room not found';
  end if;
  if not exists (select 1 from public.profiles where id = p_host_uid and is_host = true) then
    raise exception 'User bukan host (is_host=false)';
  end if;
  -- Maks 1 sesi scheduled/live per room pada rentang yang overlap.
  if exists (
    select 1 from public.room_sessions s
    where s.room_id = p_room_id
      and s.status in ('scheduled','live')
      and s.starts_at < p_ends_at
      and s.ends_at > p_starts_at
  ) then
    raise exception 'Sudah ada sesi lain di rentang waktu itu';
  end if;

  insert into public.room_sessions
    (room_id, host_uid, title, format, starts_at, ends_at, created_by)
  values
    (p_room_id, p_host_uid, trim(p_title), v_fmt, p_starts_at, p_ends_at, auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'session_id', v_id);
end;
$$;

-- ── 4. RPC start/end sesi ───────────────────────────────────
create or replace function public.start_room_session(p_session_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  v_host_name text;
  rec record;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into s from public.room_sessions where id = p_session_id;
  if not found then raise exception 'Session not found'; end if;
  if s.status <> 'scheduled' then raise exception 'Sesi tidak bisa dimulai (status %)', s.status; end if;
  if s.host_uid <> auth.uid() and not public.is_admin_request() then
    raise exception 'Hanya host sesi atau admin';
  end if;
  if exists (
    select 1 from public.room_sessions x
    where x.room_id = s.room_id and x.status = 'live' and x.id <> s.id
  ) then
    raise exception 'Masih ada sesi live lain di room ini';
  end if;

  update public.room_sessions
     set status = 'live', started_at = now()
   where id = s.id;

  -- Seed peak dari presence saat ini (tanpa dummy).
  perform public.room_session_tick(s.room_id);

  -- Notif push ke user yang menekan "Ingatkan" (pola social_push).
  select nickname into v_host_name from public.profiles where id = s.host_uid;
  for rec in
    select r.user_id from public.room_session_reminders r
    where r.session_id = s.id
  loop
    perform public.social_push(
      rec.user_id,
      coalesce(v_host_name, 'Host') || ' mulai sesi',
      s.title,
      jsonb_build_object('type','room_session','sessionId', s.id::text,
                         'roomId', s.room_id, 'title', s.title)
    );
  end loop;

  return jsonb_build_object('ok', true, 'session_id', s.id, 'room_id', s.room_id);
end;
$$;

create or replace function public.end_room_session(p_session_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into s from public.room_sessions where id = p_session_id;
  if not found then raise exception 'Session not found'; end if;
  if s.host_uid <> auth.uid() and not public.is_admin_request() then
    raise exception 'Hanya host sesi atau admin';
  end if;
  if s.status = 'live' then
    perform public.room_session_tick(s.room_id);
    update public.room_sessions
       set status = 'ended', ended_at = now()
     where id = s.id;
  elsif s.status = 'scheduled' then
    update public.room_sessions
       set status = 'cancelled', ended_at = now()
     where id = s.id;
  else
    raise exception 'Sesi sudah %', s.status;
  end if;
  return jsonb_build_object('ok', true, 'session_id', s.id);
end;
$$;

-- ── 5. RPC lobby: sesi live/terdekat per room ───────────────
create or replace function public.next_room_sessions(p_room_ids text[])
returns table (
  room_id text, session_id bigint, title text, format text,
  starts_at timestamptz, ends_at timestamptz, status text,
  host_uid uuid, host_name text, host_avatar text,
  peak_viewers int, gifts_total int, reminded boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (s.room_id)
    s.room_id, s.id, s.title, s.format, s.starts_at, s.ends_at, s.status,
    s.host_uid, p.nickname, p.avatar,
    s.peak_viewers, s.gifts_total,
    exists (
      select 1 from public.room_session_reminders r
      where r.session_id = s.id and r.user_id = auth.uid()
    )
  from public.room_sessions s
  join public.profiles p on p.id = s.host_uid
  where s.room_id = any (p_room_ids)
    and s.status in ('live','scheduled')
  order by s.room_id,
           case when s.status = 'live' then 0 else 1 end,
           s.starts_at asc;
$$;

-- ── 6. RPC reminder ─────────────────────────────────────────
create or replace function public.toggle_session_reminder(p_session_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.room_sessions where id = p_session_id and status = 'scheduled'
  ) then
    raise exception 'Sesi tidak tersedia untuk diingatkan';
  end if;
  if exists (
    select 1 from public.room_session_reminders
    where session_id = p_session_id and user_id = uid
  ) then
    delete from public.room_session_reminders
     where session_id = p_session_id and user_id = uid;
    return jsonb_build_object('ok', true, 'reminded', false);
  end if;
  insert into public.room_session_reminders (session_id, user_id)
  values (p_session_id, uid)
  on conflict do nothing;
  return jsonb_build_object('ok', true, 'reminded', true);
end;
$$;

-- ── 7. RPC mute oleh host sesi live ─────────────────────────
-- Sama dengan room_voice_mute, tapi izin diperluas: host sesi live
-- di room tersebut boleh mute speaker (task 3b).
create or replace function public.session_host_mute(p_room_id text, p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
    or exists (select 1 from public.room_sessions s
                where s.room_id = p_room_id and s.status = 'live'
                  and s.host_uid = me)
    or public.is_admin_request()
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
$$;

-- ── 8. RPC tick KPI (peak viewers, tanpa dummy) ─────────────
create or replace function public.room_session_tick(p_room_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_viewers int := 0;
  v_peak int := 0;
begin
  select id into v_id from public.room_sessions
   where room_id = p_room_id and status = 'live'
   order by started_at desc limit 1;
  if v_id is null then
    return jsonb_build_object('ok', true, 'live', false, 'viewers', 0);
  end if;

  select count(*) into v_viewers
    from public.room_presence rp
   where rp.room_id = p_room_id
     and not exists (select 1 from public.dummy_accounts d where d.uid = rp.user_id);

  update public.room_sessions
     set peak_viewers = greatest(peak_viewers, v_viewers)
   where id = v_id
   returning peak_viewers into v_peak;

  return jsonb_build_object('ok', true, 'live', true,
                            'viewers', v_viewers, 'peak', v_peak);
end;
$$;

-- ── 9. RPC sweep: auto-end + tick (cron) ────────────────────
create or replace function public.room_session_sweep()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int := 0;
  r record;
begin
  -- Auto-end: live > ends_at + 2 jam.
  update public.room_sessions
     set status = 'ended', ended_at = now()
   where status = 'live' and ends_at + interval '2 hours' < now();
  get diagnostics v_n = row_count;

  -- Tick peak untuk sesi live yang masih berjalan.
  for r in select room_id from public.room_sessions where status = 'live' loop
    perform public.room_session_tick(r.room_id);
  end loop;

  return v_n;
end;
$$;

-- ── 10. send_room_gift v2 — aktif lagi, ekonomi paid-only ───
create or replace function public.send_room_gift(
  p_room_id text, p_gift_id text, p_qty int default 1
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  g record; r record; sess record; points_on boolean; cut_pct int; tx_max int;
  my_name text; my_gender text; am_registered boolean;
  n int; cut int; net int; paid int; remaining int;
  host_id uuid; is_session boolean := false;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  perform pg_advisory_xact_lock(hashtext('wallet:' || uid::text));
  if p_qty is null or p_qty < 1 or p_qty > 20 then
    raise exception 'Invalid qty';
  end if;

  select points_enabled, coalesce(gift_cut_pct,30), coin_tx_max_per_hour
    into points_on, cut_pct, tx_max from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(),'') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;
  select is_registered, nickname, gender
    into am_registered, my_name, my_gender from profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;
  if my_gender = 'female' then
    raise exception 'Female cannot send gift' using errcode = '42501';
  end if;
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins * p_qty;

  select * into r from rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;

  if r.is_private is true then
    -- Private room: penerima = owner (perilaku lama).
    if r.expires_at is not null and r.expires_at <= now() then
      raise exception 'Room expired';
    end if;
    host_id := r.owner_id;
    if host_id is null then raise exception 'Room has no host'; end if;
    if r.owner_id <> uid
       and not exists (select 1 from room_members rm
                        where rm.room_id = p_room_id and rm.user_id = uid) then
      raise exception 'Not a room member';
    end if;
  else
    -- Room global: hanya saat ada sesi live; penerima = host sesi.
    select * into sess from room_sessions
     where room_id = p_room_id and status = 'live'
     order by started_at desc limit 1;
    if not found then
      raise exception 'Tidak ada sesi live di room ini' using errcode = '22023';
    end if;
    host_id := sess.host_uid;
    is_session := true;
  end if;

  if host_id = uid then raise exception 'Cannot gift self'; end if;

  -- Gift WAJIB koin beli/penghasilan (pola send_gift 2026-11-10):
  -- bonus hanya boleh menambal lewat promo plafon (ledger_spend_promo).
  paid := public.yukcoin_spendable(uid, host_id, 100 - cut_pct);
  if paid < n then
    raise exception 'Gift membutuhkan koin beli/penghasilan (top-up dulu)'
      using errcode = '22023';
  end if;

  remaining := public.ledger_spend_promo(uid, 'gift_sent', n, p_room_id,
    host_id, 100 - cut_pct);

  cut := (n * cut_pct) / 100;
  net := n - cut;

  if net > 0 then
    perform public.ledger_credit(host_id, 'earned', 'gift_recv', net,
      p_room_id, jsonb_build_object('gift', p_gift_id, 'qty', p_qty,
                                    'from', uid, 'tier', 'paid'));
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, host_id, p_room_id,
              jsonb_build_object('gift', p_gift_id, 'qty', p_qty,
                                 'gross', n, 'net', net, 'pct', cut_pct,
                                 'session', is_session));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n,
            jsonb_build_object('gift', p_gift_id, 'qty', p_qty, 'tier', 'paid')),
           (host_id, 'gift_recv', net,
            jsonb_build_object('gift', p_gift_id, 'qty', p_qty, 'tier', 'paid'));

  insert into public.messages
    (room_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_room_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  if is_session then
    update public.room_sessions
       set gifts_total = gifts_total + n
     where id = sess.id;
  end if;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'qty', p_qty, 'gross', n, 'net', net, 'cut', cut,
    'tier', 'paid', 'host', host_id, 'session', is_session);
end;
$$;

-- ── 11. Admin KPI sesi ──────────────────────────────────────
create or replace function public.admin_room_session_stats(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'sessions', count(*),
    'ended', count(*) filter (where status = 'ended'),
    'live', count(*) filter (where status = 'live'),
    'scheduled', count(*) filter (where status = 'scheduled'),
    'on_time_pct', coalesce(round(
      100.0 * count(*) filter (where started_at is not null
                                and started_at <= starts_at + interval '15 minutes')
      / nullif(count(*) filter (where started_at is not null), 0), 1), 0),
    'avg_duration_min', coalesce(round(avg(
      extract(epoch from (ended_at - started_at)) / 60.0)
      filter (where started_at is not null and ended_at is not null), 0), 0),
    'avg_peak_viewers', coalesce(round(avg(peak_viewers)), 0),
    'total_gifts', coalesce(sum(gifts_total), 0)
  ) into v
  from public.room_sessions
  where starts_at >= now() - make_interval(days => greatest(p_days, 1));
  return v;
end;
$$;

-- ── 12. Grant RPC ───────────────────────────────────────────
revoke execute on function public.admin_set_host(uuid, boolean) from public, anon;
revoke execute on function public.schedule_room_session(text, uuid, text, text, timestamptz, timestamptz) from public, anon;
revoke execute on function public.start_room_session(bigint) from public, anon;
revoke execute on function public.end_room_session(bigint) from public, anon;
revoke execute on function public.next_room_sessions(text[]) from public, anon;
revoke execute on function public.toggle_session_reminder(bigint) from public, anon;
revoke execute on function public.session_host_mute(text, uuid) from public, anon;
revoke execute on function public.room_session_tick(text) from public, anon;
revoke execute on function public.room_session_sweep() from public, anon, authenticated;
revoke execute on function public.admin_room_session_stats(int) from public, anon;
revoke execute on function public.send_room_gift(text, text, int) from public, anon;

grant execute on function public.schedule_room_session(text, uuid, text, text, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function public.start_room_session(bigint) to authenticated, service_role;
grant execute on function public.end_room_session(bigint) to authenticated, service_role;
grant execute on function public.next_room_sessions(text[]) to authenticated, service_role;
grant execute on function public.toggle_session_reminder(bigint) to authenticated, service_role;
grant execute on function public.session_host_mute(text, uuid) to authenticated, service_role;
grant execute on function public.room_session_tick(text) to authenticated, service_role;
grant execute on function public.room_session_sweep() to service_role;
grant execute on function public.admin_room_session_stats(int) to authenticated, service_role;
grant execute on function public.send_room_gift(text, text, int) to authenticated, service_role;
grant execute on function public.admin_set_host(uuid, boolean) to authenticated, service_role;
