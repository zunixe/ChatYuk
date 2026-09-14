-- ============================================================
-- Consent-based adult mode (per chat)
--
-- Flow (permintaan owner):
--   1. Chat panjang + saling kenal (bukan fase awal) → AI bertanya
--      natural ke user: "kamu mau aku nakal, atau kamu suka aku nakal?"
--   2. Jawaban ya → mode vulgar AKTIF untuk chat itu (AI ikut dewasa).
--      Jawaban tidak → tidak pernah ditawari lagi.
--   3. Tanpa consent → guard NSFW tetap keras.
--
-- ai_chat_state: RLS on + tanpa policy = hanya service_role (edge
-- function) yang bisa akses. Guard admin global tetap di atasnya.
-- ============================================================

create table if not exists public.ai_chat_state (
  chat_id    text primary key,
  adult_mode boolean not null default false,
  asked_at   timestamptz,
  declined   boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.ai_chat_state enable row level security;

revoke all on table public.ai_chat_state from anon, authenticated;
grant all on table public.ai_chat_state to service_role;
