-- ============================================
-- ChatYuk Supabase Schema
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================

-- ── PROFILES ──
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null default 'Anon',
  gender text not null default 'male',
  age int not null default 0,
  country text not null default 'Indonesia',
  city text not null default 'Jakarta',
  ip_address text not null default '',
  status text not null default 'offline',
  avatar text not null default '',
  fcm_token text not null default '',
  login_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select" on public.profiles
  for select using (true);

create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- ── ROOMS ──
create table if not exists public.rooms (
  id text primary key,
  name text not null,
  description text not null default '',
  icon text not null default '💬',
  "order" int not null default 0,
  country text not null default 'Indonesia',
  category text not null default 'general'
);

alter table public.rooms enable row level security;

create policy "rooms_select" on public.rooms
  for select using (true);

-- ── ROOM MESSAGES ──
create table if not exists public.messages (
  id bigint generated always as identity primary key,
  room_id text not null references public.rooms (id) on delete cascade,
  sender_id uuid not null,
  sender_name text not null default 'Anon',
  sender_gender text not null default 'other',
  text text not null default '',
  type text not null default 'text',
  image_data text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists messages_room_created_idx
  on public.messages (room_id, created_at desc);

alter table public.messages enable row level security;

create policy "messages_select" on public.messages
  for select using (true);

create policy "messages_insert" on public.messages
  for insert with check (auth.uid() = sender_id);

-- ── PRIVATE CHATS ──
create table if not exists public.private_chats (
  chat_id text primary key,
  participants uuid[] not null,
  participant_names jsonb not null default '{}',
  participant_genders jsonb not null default '{}',
  participant_locations jsonb not null default '{}',
  participant_ages jsonb not null default '{}',
  last_message text not null default '',
  last_message_at timestamptz not null default now(),
  unread_counts jsonb not null default '{}',
  last_read_at jsonb not null default '{}',
  hidden_by uuid[] not null default '{}',
  hidden_at jsonb not null default '{}'
);

alter table public.private_chats enable row level security;

create policy "private_chats_select" on public.private_chats
  for select using (auth.uid() = any (participants));

create policy "private_chats_insert" on public.private_chats
  for insert with check (auth.uid() = any (participants));

create policy "private_chats_update" on public.private_chats
  for update using (auth.uid() = any (participants));

-- ── PRIVATE MESSAGES ──
create table if not exists public.private_messages (
  id bigint generated always as identity primary key,
  chat_id text not null references public.private_chats (chat_id) on delete cascade,
  sender_id uuid not null,
  sender_name text not null default 'Anon',
  sender_gender text not null default 'other',
  text text not null default '',
  type text not null default 'text',
  image_data text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists private_messages_chat_created_idx
  on public.private_messages (chat_id, created_at desc);

alter table public.private_messages enable row level security;

create policy "private_messages_select" on public.private_messages
  for select using (
    -- Peserta chat bisa lihat pesan, KECUALI pesan dari orang yang diblokir
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid()
        and b.blocked_id = private_messages.sender_id
    )
  );

create policy "private_messages_insert" on public.private_messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Tidak bisa kirim pesan jika diblokir oleh penerima
    and not exists (
      select 1 from public.blocks b
      where b.blocked_id = auth.uid()
        and b.blocker_id = (
          select unnest(participants) from public.private_chats
          where chat_id = private_messages.chat_id
            and unnest(participants) != auth.uid()
          limit 1
        )
    )
  );

-- ── BLOCKS ──
create table if not exists public.blocks (
  blocker_id uuid not null,
  blocked_id uuid not null,
  blocked_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

alter table public.blocks enable row level security;

create policy "blocks_select_own" on public.blocks
  for select using (auth.uid() = blocker_id);

create policy "blocks_insert_own" on public.blocks
  for insert with check (auth.uid() = blocker_id);

create policy "blocks_delete_own" on public.blocks
  for delete using (auth.uid() = blocker_id);

-- ── REPORTS ──
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null,
  reported_id uuid not null,
  reason text not null default '',
  created_at timestamptz not null default now()
);

alter table public.reports enable row level security;

create policy "reports_insert_own" on public.reports
  for insert with check (auth.uid() = reporter_id);

-- ── ROOM PRESENCE (online users in room) ──
create table if not exists public.room_presence (
  room_id text not null references public.rooms (id) on delete cascade,
  user_id uuid not null,
  nickname text not null default 'Anon',
  gender text not null default 'other',
  age int not null default 0,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.room_presence enable row level security;

create policy "room_presence_select" on public.room_presence
  for select using (true);

create policy "room_presence_insert_own" on public.room_presence
  for insert with check (auth.uid() = user_id);

create policy "room_presence_delete_own" on public.room_presence
  for delete using (auth.uid() = user_id);

create policy "room_presence_update_own" on public.room_presence
  for update using (auth.uid() = user_id);

-- Enable realtime for presence & messages
alter publication supabase_realtime add table public.room_presence;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.private_messages;
alter publication supabase_realtime add table public.private_chats;
alter publication supabase_realtime add table public.profiles;

-- ── SEED ROOMS ──
insert into public.rooms (id, name, description, icon, "order") values
  ('general', 'General', 'Obrolan umum untuk semua', '💬', 1),
  ('curhat', 'Curhat', 'Cerita dan curhat bareng', '🤗', 2),
  ('pertemanan', 'Pertemanan', 'Cari temen baru di sini', '🤝', 3),
  ('teknologi', 'Teknologi', 'Diskusi tech & gadget', '💻', 4),
  ('gaming', 'Gaming', 'Main bareng & diskusi game', '🎮', 5),
  ('musik', 'Musik', 'Sharing musik & lagu', '🎵', 6),
  ('film', 'Film & TV', 'Rekomendasi & review film', '🎬', 7),
  ('joke', 'Joke & Meme', 'Yang bikin ngakak', '😂', 8),
  ('belajar', 'Belajar', 'Diskusi belajar & kuliah', '📚', 9),
  ('flirt', 'Flirt', 'Ngobrol santai & asyik', '😉', 10)
on conflict (id) do nothing;
