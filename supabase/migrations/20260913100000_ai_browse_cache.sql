-- ============================================================
-- Ronde 2 review: cache browsing sonar + index presence tick
--
-- P1 #5: lookupFreshInfo dipanggil per pesan yang cocok regex → pollen
--   linear dengan pertanyaan berita. Tabel cache kecil: jawaban per
--   topik dinormalisasi, TTL 1 jam (berita!), bersih-bersih malas.
-- P1 #8: ai_presence_tick join+filter dummy_accounts tiap 5 menit tanpa
--   index → tambah index ai_enabled.
-- ============================================================

create table if not exists public.ai_browse_cache (
  topic_key text primary key,
  answer text not null,
  created_at timestamptz not null default now()
);

alter table public.ai_browse_cache enable row level security;
revoke all on table public.ai_browse_cache from anon, authenticated;
grant select, insert, update, delete on table public.ai_browse_cache
  to service_role;

create index if not exists idx_dummy_accounts_ai_enabled
  on public.dummy_accounts (ai_enabled);
