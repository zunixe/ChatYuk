-- ============================================================
-- Kehidupan harian AI dummy — cerita per hari sebagai topik obrolan
--
-- Permintaan owner:
--   - AI generate cerita harian: kegiatan apa saja, kerja apa + masalah
--     di kantor, main dengan teman, jalan-jalan ke mana (tempat nyata
--     sesuai kota dummy).
--   - Nyambung antar hari (hari ini melanjutkan kemarin).
--   - Dipakai sebagai topik NATURAL saat ditanya di obrolan ("lagi apa",
--     "sibuk apa", "kamu di mana"), bukan dongeng sekaligus.
-- ============================================================

create table if not exists public.ai_daily_story (
  dummy_uid  uuid not null,
  story_date date not null,
  story      jsonb not null, -- {summary, work, problem, activities[], hangout, place}
  created_at timestamptz not null default now(),
  primary key (dummy_uid, story_date)
);

alter table public.ai_daily_story enable row level security;

revoke all on table public.ai_daily_story from anon, authenticated;
grant all on table public.ai_daily_story to service_role;
