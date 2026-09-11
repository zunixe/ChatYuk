-- ChatYuk: memori jangka panjang AI dummy per lawan bicara.
-- Fakta-fakta tentang user (nama, kerja, hobi, sifat, rencana) diekstrak
-- otomatis dari percakapan dan diingat untuk sesi berikutnya.
-- Akses HANYA service_role (edge function) — user tidak bisa baca/tulis.
-- ============================================================

create table if not exists public.ai_memory (
  dummy_uid  uuid not null,
  user_id    uuid not null,
  fact       text not null,
  created_at timestamptz not null default now(),
  primary key (dummy_uid, user_id, fact)
);

alter table public.ai_memory enable row level security;
revoke all on table public.ai_memory from anon, authenticated;
grant select, insert, delete on table public.ai_memory to service_role;

create index if not exists idx_ai_memory_pair
  on public.ai_memory (dummy_uid, user_id, created_at desc);
