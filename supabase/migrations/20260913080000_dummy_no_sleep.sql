-- Batch 1 human-like: kill-switch jam tidur per dummy.
-- ai_no_sleep = true → dummy ini selalu responsif (testing), abaikan
-- aturan tidur random 20–23 / bangun 4–6 dan jumatan di ai-reply.
-- Default false = ikut aturan tidur. Diubah via SQL (belum ada toggle UI).
alter table public.dummy_accounts
  add column if not exists ai_no_sleep boolean not null default false;
