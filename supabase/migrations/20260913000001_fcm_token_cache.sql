-- Cache token akses FCM lintas-invokasi edge function.
-- getAccessToken (_shared/fcm.ts) membaca/menulis baris ini supaya cold-start
-- isolate baru tidak perlu sign RSA + HTTP ke Google bila token masih segar.
-- Hanya service_role yang boleh akses (tanpa policy = deny anon/authenticated).
create table if not exists public.fcm_token_cache (
  service text primary key,
  token text not null,
  exp_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.fcm_token_cache enable row level security;
