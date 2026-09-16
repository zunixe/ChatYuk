-- menyentuh: (tidak ada fungsi frozen)
-- Ingatan jangka-panjang AI: ringkasan percakapan lama per (dummy, user).
-- AI hanya bisa memuat window pesan terbatas sebagai konteks; pesan lama
-- yang di luar window dirangkum di sini supaya dummy tetap "ingat" obrolan
-- jauh (mis. janji, nama, cerita hidup lawan bicara) tanpa boros token.
create table if not exists public.ai_chat_summary (
  dummy_uid uuid not null,
  user_id uuid not null,
  summary text not null default '',
  covered_count int not null default 0,   -- jumlah pesan yang sudah dirangkum
  updated_at timestamptz not null default now(),
  primary key (dummy_uid, user_id)
);

-- Hanya service_role (edge) yang akses — client TIDAK butuh.
alter table public.ai_chat_summary enable row level security;
revoke all on public.ai_chat_summary from public, anon, authenticated;
grant all on public.ai_chat_summary to service_role;
