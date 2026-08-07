-- ============================================
-- ChatYuk: Galeri Foto Pribadi
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================

-- ── USER_PHOTOS ──
create table if not exists public.user_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  photo text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists user_photos_user_id_idx on public.user_photos (user_id);

alter table public.user_photos enable row level security;

create policy "user_photos_select" on public.user_photos
  for select using (true);

create policy "user_photos_insert_own" on public.user_photos
  for insert with check (auth.uid() = user_id);

create policy "user_photos_delete_own" on public.user_photos
  for delete using (auth.uid() = user_id);