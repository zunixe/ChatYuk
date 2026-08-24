-- ============================================================
-- ChatYuk: Admin call monitor (badge call aktif + pantau call)
--
-- 1) Ensure idempotent tabel call_signals (signaling WebRTC).
--    Tabel aslinya dibuat langsung di server tanpa migrasi repo;
--    definisi ini identik dengan pemakaian CallService.
-- 2) RLS + policy: peserta call boleh baca/kirim sinyal call-nya,
--    admin (zunixe@gmail.com) boleh baca/kirim semua (fitur pantau).
-- 3) RPC admin_active_calls(): daftar call aktif untuk badge monitor.
-- 4) RPC is_chatyuk_admin(p_uid): verifikasi client-side bahwa peminta
--    "watch" benar-benar admin — user menolak permintaan non-admin.
-- ============================================================

-- ── 1. Tabel call_signals (skip jika sudah ada di server) ──
create table if not exists public.call_signals (
  id bigint generated always as identity primary key,
  call_id uuid not null references public.calls(id) on delete cascade,
  from_uid uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists call_signals_call_idx
  on public.call_signals (call_id, created_at);

do $$ begin
  alter publication supabase_realtime add table public.call_signals;
exception when duplicate_object then null;
when undefined_table then null;
end $$;

-- ── 2. RLS + policy ──
alter table public.call_signals enable row level security;

drop policy if exists call_signals_select on public.call_signals;
create policy call_signals_select on public.call_signals
  for select using (
    exists (
      select 1 from public.calls c
      where c.id = call_id
        and (c.caller_id = auth.uid() or c.callee_id = auth.uid())
    )
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );

drop policy if exists call_signals_insert on public.call_signals;
create policy call_signals_insert on public.call_signals
  for insert with check (
    from_uid = auth.uid()
    and (
      exists (
        select 1 from public.calls c
        where c.id = call_id
          and (c.caller_id = auth.uid() or c.callee_id = auth.uid())
      )
      or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
    )
  );

-- ── 3. RPC daftar call aktif (admin only) ──
create or replace function public.admin_active_calls()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
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
$$;

revoke execute on function public.admin_active_calls() from public, anon;
grant execute on function public.admin_active_calls() to authenticated, service_role;

-- ── 4. RPC verifikasi admin (dipakai device user sebelum melayani watch) ──
create or replace function public.is_chatyuk_admin(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from auth.users u
    where u.id = p_uid and u.email = 'zunixe@gmail.com'
  );
$$;

revoke execute on function public.is_chatyuk_admin(uuid) from public, anon;
grant execute on function public.is_chatyuk_admin(uuid) to authenticated, service_role;
