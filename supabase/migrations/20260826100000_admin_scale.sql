-- ============================================================
-- Optimasi skala jutaan user untuk panel admin.
-- P0-1: admin_stats dari cache TTL 5 menit (bukan ~12 agregasi
--       full-table tiap poll). Pull-to-refresh pakai admin_stats_force().
-- P0-2: index partial yang dipakai agregasi & polling.
-- P0-3: admin_list_devices total = estimasi reltuples (O(1)),
--       bukan count(*) full-scan tiap poll device.
-- P0-4: retensi call_signals — sinyal call berakhir >1 jam dibuang
--       di admin_sweep_calls agar tabel tidak membengkak.
-- ============================================================

-- ── A. Cache statistik ──────────────────────────────────────────────────────
create table if not exists public.admin_stats_cache(
  id integer primary key default 1,
  data jsonb,
  refreshed_at timestamptz not null default now()
);
insert into public.admin_stats_cache(id) values (1) on conflict do nothing;

-- Badan komputasi lama dipindah utuh ke sini (dipanggil saat cache basi).
create or replace function public.admin_stats_compute()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'total_users', (select count(*) from profiles),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'),
    'registered_users', (select count(*) from profiles where is_registered = true),
    'anonymous_users', (select count(*) from profiles where is_registered = false),
    'messages_today',
      (select count(*) from private_messages where created_at >= current_date at time zone 'Asia/Jakarta') +
      (select count(*) from messages where created_at >= current_date at time zone 'Asia/Jakarta'),
    'rooms_active', (select count(distinct room_id) from room_presence),
    'avg_points', (select round(avg(points)) from profiles),
    'total_points', (select sum(points) from profiles),
    'top_earners', (select coalesce(jsonb_agg(
      jsonb_build_object('nickname', nickname, 'points', points, 'uid', id)
      order by points desc), '[]'::jsonb) from (select id, nickname, points from profiles order by points desc limit 10) t),
    'stuck_users', (select count(*) from profiles
      where points = 0 and last_seen >= (now() - interval '7 days')),
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object('reported_id', reported_id, 'report_count', c)
      order by c desc), '[]'::jsonb)
      from (select reported_id, count(*) as c from reports
            group by reported_id order by c desc limit 20) sub),
    'points_enabled', (select points_enabled from app_settings where id = 'global')
  ) into result;
  return result;
end;
$fn$;

-- Baca cache; recompute paling sering tiap 5 menit walau dipoll tiap detik.
create or replace function public.admin_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_data jsonb;
  v_at timestamptz;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select data, refreshed_at into v_data, v_at
    from public.admin_stats_cache where id = 1;

  if v_data is null or v_at is null
     or v_at < now() - interval '5 minutes' then
    v_data := public.admin_stats_compute();
    update public.admin_stats_cache
       set data = v_data, refreshed_at = now()
     where id = 1;
  end if;

  -- info tambahan untuk UI "terakhir diperbarui"
  return jsonb_set(v_data, '{refreshed_at}',
    to_jsonb(coalesce(v_at, now())));
end;
$fn$;

-- Paksa hitung ulang sekarang (pull-to-refresh).
create or replace function public.admin_stats_force()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_data jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  v_data := public.admin_stats_compute();
  update public.admin_stats_cache
     set data = v_data, refreshed_at = now()
   where id = 1;
  return jsonb_set(v_data, '{refreshed_at}', to_jsonb(now()));
end;
$fn$;

revoke execute on function public.admin_stats_compute() from public, anon;
revoke execute on function public.admin_stats() from public, anon;
revoke execute on function public.admin_stats_force() from public, anon;
grant execute on function public.admin_stats() to authenticated, service_role;
grant execute on function public.admin_stats_force() to authenticated, service_role;

-- ── B. Index partial untuk agregasi & filter populer ────────────────────────
create index if not exists idx_profiles_last_seen
  on public.profiles(last_seen desc nulls last);
create index if not exists idx_profiles_registered
  on public.profiles(is_registered);
create index if not exists idx_profiles_points_desc
  on public.profiles(points desc);
create index if not exists idx_privmsgs_created_at
  on public.private_messages(created_at);
create index if not exists idx_msgs_created_at
  on public.messages(created_at);

-- ── C. Total device: estimasi O(1), bukan count(*) ──────────────────────────
create or replace function public.admin_list_devices(p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_total bigint;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  -- Estimasi jumlah baris dari planner stats: murah & cukup utk badge.
  select greatest(coalesce(reltuples, 0), 0)::bigint into v_total
    from pg_class
   where oid = 'public.user_devices'::regclass;

  select jsonb_build_object(
    'total', coalesce(v_total, 0),
    'items', coalesce((
      select jsonb_agg(sub.obj order by sub.last_seen_at desc nulls last)
      from (
        select
          jsonb_build_object(
            'user_id',      p.id,
            'nickname',     p.nickname,
            'email',        p.email,
            'is_registered', p.is_registered,
            'profile_status', p.status,
            'install_id',   d.install_id,
            'brand',        d.brand,
            'model',        d.model,
            'os_name',      d.os_name,
            'os_version',   d.os_version,
            'app_version',  d.app_version,
            'ip_address',   d.ip_address,
            'last_seen_at', d.last_seen_at,
            'is_active',    d.is_active,
            'created_at',   d.created_at
          ) as obj,
          d.last_seen_at
        from public.user_devices d
        left join public.profiles p on p.id = d.user_id
        order by d.last_seen_at desc nulls last
        limit greatest(p_limit, 1) offset greatest(p_offset, 0)
      ) sub
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_list_devices(integer,integer) from public, anon;

-- ── D. Retensi call_signals (dijalankan bersama sweep zombie) ───────────────
create or replace function public.admin_sweep_calls()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_ringing int;
  v_answered int;
  v_signals int;
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'zunixe@gmail.com'
     and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  -- Ringing tak pernah dijawab > 90 detik
  update public.calls
     set status = 'missed', ended_at = now()
   where status = 'ringing'
     and created_at < now() - interval '90 seconds';
  get diagnostics v_ringing = row_count;

  -- Answered tapi heartbeat mati > 75 detik (app ditutup paksa / crash)
  update public.calls
     set status = 'ended', ended_at = now()
   where status = 'answered'
     and ended_at is null
     and coalesce(last_seen_at, answered_at, created_at) < now() - interval '75 seconds';
  get diagnostics v_answered = row_count;

  -- Sinyal call yang sudah berakhir > 1 jam tidak berguna lagi —
  -- tanpa ini tabel call_signals membengkak dan memperlambat realtime.
  delete from public.call_signals s
   using public.calls c
   where s.call_id = c.id
     and c.status in ('ended','missed','canceled','declined')
     and c.ended_at is not null
     and c.ended_at < now() - interval '1 hour';
  get diagnostics v_signals = row_count;

  return v_ringing + v_answered + v_signals;
end;
$fn$;
