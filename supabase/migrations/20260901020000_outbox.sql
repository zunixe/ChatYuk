-- P0: outbox queue ganti net.http_post blocking di trigger
create table if not exists public.outbox (
  id bigserial primary key,
  type text not null,
  payload jsonb not null,
  created_at timestamptz default now(),
  sent_at timestamptz
);
create index if not exists idx_outbox_unsent on public.outbox(sent_at) where sent_at is null;

-- Worker cron via Dashboard: POST https://.../functions/v1/outbox-worker tiap 5s
-- (tidak pakai vault di migration, cukup tabel)
