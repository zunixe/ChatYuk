-- Call monitor realtime & anti-zombie
-- 1) last_seen_at = heartbeat peserta (touch_call tiap ~15s selama call hidup)
-- 2) admin_sweep_calls: akhiri ringing kadaluarsa & answered tanpa heartbeat
-- 3) admin_active_calls: tanpa cutoff waktu — kebenaran dari ended_at/sweep
-- 4) policy SELECT utk admin agar realtime postgres_changes terkirim

alter table public.calls add column if not exists last_seen_at timestamptz;
create index if not exists calls_open_idx on public.calls (status)
  where ended_at is null;

-- Heartbeat peserta call (security definer supaya lolos RLS update)
create or replace function public.touch_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  update public.calls
     set last_seen_at = now()
   where id = p_call_id
     and ended_at is null
     and auth.uid() in (caller_id, callee_id);
end;
$fn$;

-- Akhiri call zombie. Hanya admin.
create or replace function public.admin_sweep_calls()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_ringing int;
  v_answered int;
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

  return v_ringing + v_answered;
end;
$fn$;

-- Daftar aktif: kebenaran penuh dari kolom status/ended_at.
-- Zombie dibersihkan admin_sweep_calls yang dipanggil fetchActiveCalls.
create or replace function public.admin_active_calls()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case
    when coalesce(auth.jwt() ->> 'email', '') <> 'zunixe@gmail.com'
      then '[]'::jsonb
    else coalesce((
      select jsonb_agg(t order by t.created_at desc)
      from (
        select
          c.id::text as id,
          case when c.caller_id::text < c.callee_id::text
            then c.caller_id::text || '_' || c.callee_id::text
            else c.callee_id::text || '_' || c.caller_id::text
          end as chat_id,
          c.caller_id::text as caller_id,
          c.callee_id::text as callee_id,
          coalesce(pc.nickname, 'Unknown') as caller_name,
          coalesce(pd.nickname, 'Unknown') as callee_name,
          c.call_type,
          c.status,
          c.created_at,
          c.answered_at
        from public.calls c
        left join public.profiles pc on pc.id = c.caller_id
        left join public.profiles pd on pd.id = c.callee_id
        where (c.status = 'answered' and c.ended_at is null)
           or (c.status = 'ringing' and c.created_at > now() - interval '60 seconds')
      ) t
    ), '[]'::jsonb)
  end;
$fn$;

-- Admin boleh baca semua call (untuk realtime postgres_changes di client)
drop policy if exists calls_select_admin on public.calls;
create policy calls_select_admin on public.calls
  for select
  using (coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com');
