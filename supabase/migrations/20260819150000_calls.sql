-- ============================================================
-- ChatYuk: Call 1:1 audio/video (WebRTC)
-- Tabel calls: status call + trigger push FCM "call masuk".
-- Signaling SDP/ICE TIDAK lewat DB — pakai Realtime broadcast
-- channel `call-signal-<callId>` (murni client-side).
-- ============================================================

create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references public.profiles(id) on delete cascade,
  callee_id uuid not null references public.profiles(id) on delete cascade,
  call_type text not null default 'video' check (call_type in ('audio', 'video')),
  status text not null default 'ringing' check (status in
    ('ringing', 'answered', 'declined', 'canceled', 'ended', 'missed', 'busy')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz
);

create index if not exists calls_callee_idx on public.calls (callee_id, created_at desc);
create index if not exists calls_caller_idx on public.calls (caller_id, created_at desc);

-- WAJIB: tanpa ini Realtime Postgres Changes tidak pernah mengirim event
-- (call masuk tidak muncul di callee meski app terbuka).
alter publication supabase_realtime add table public.calls;

alter table public.calls enable row level security;

create policy calls_select on public.calls
  for select using (auth.uid() = caller_id or auth.uid() = callee_id);
create policy calls_insert on public.calls
  for insert with check (auth.uid() = caller_id);
create policy calls_update on public.calls
  for update using (auth.uid() = caller_id or auth.uid() = callee_id);

-- ── Push FCM "call masuk" (data-only, teks dirender client = bilingual) ──
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text
) returns void language plpgsql security definer set search_path = public as $$
declare
  t text;
begin
  select fcm_token into t from public.profiles where id = p_callee;
  if t is not null and t <> '' then
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
      body := jsonb_build_object(
        'token', t,
        'title', p_caller_name,
        'body', p_call_type,
        'data', jsonb_build_object(
          'type', 'call',
          'callId', p_call,
          'callerUid', p_caller,
          'fromName', p_caller_name,
          'callType', p_call_type
        )
      )
    );
  end if;
end; $$;

-- ── Trigger: insert status ringing → kirim push ke callee ──
create or replace function public.notify_call_ringing() returns trigger as $$
declare
  caller_name text;
begin
  begin
    if new.status <> 'ringing' then
      return new;
    end if;
    select nickname into caller_name from public.profiles where id = new.caller_id;
    perform public.call_push(
      new.callee_id, new.id, new.caller_id,
      coalesce(caller_name, 'Anon'), new.call_type
    );
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

drop trigger if exists notify_call_ringing_trigger on public.calls;
create trigger notify_call_ringing_trigger
  after insert on public.calls
  for each row
  execute function public.notify_call_ringing();