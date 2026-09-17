-- Long-press ala WA: reaksi emoji + bintang + label Teruskan.
-- Tabel baru saja, tidak menyentuh fungsi FROZEN.

-- Label "Diteruskan" di bubble: flag di kedua tabel pesan.
alter table public.private_messages
  add column if not exists is_forwarded boolean not null default false;
alter table public.messages
  add column if not exists is_forwarded boolean not null default false;

-- Reaksi per pesan: satu baris = satu user + satu emoji.
-- chat_type: 'private' (private_messages) atau 'room' (messages).
-- message_id teks supaya muat id bigint maupun string pending.
create table if not exists public.message_reactions (
  id bigint generated always as identity primary key,
  chat_type text not null check (chat_type in ('private', 'room')),
  chat_id text not null,
  message_id text not null,
  user_id uuid not null,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique (chat_type, message_id, user_id, emoji)
);
create index if not exists idx_msg_reactions_chat_msg
  on public.message_reactions (chat_id, message_id);
create index if not exists idx_msg_reactions_user
  on public.message_reactions (user_id);

alter table public.message_reactions enable row level security;

drop policy if exists message_reactions_select on public.message_reactions;
create policy message_reactions_select on public.message_reactions
  for select using (
    -- Room: semua user login boleh lihat (pesan room memang publik).
    (chat_type = 'room' and auth.uid() is not null)
    -- Private: hanya peserta chat.
    or (
      chat_type = 'private'
      and exists (
        select 1 from public.private_chats pc
        where pc.chat_id = message_reactions.chat_id
          and auth.uid() = any (pc.participants)
      )
    )
  );

drop policy if exists message_reactions_insert on public.message_reactions;
create policy message_reactions_insert on public.message_reactions
  for insert with check (
    auth.uid() = user_id
    and (
      (chat_type = 'room')
      or exists (
        select 1 from public.private_chats pc
        where pc.chat_id = message_reactions.chat_id
          and auth.uid() = any (pc.participants)
      )
    )
  );

drop policy if exists message_reactions_delete on public.message_reactions;
create policy message_reactions_delete on public.message_reactions
  for delete using (auth.uid() = user_id);

-- Pesan berbintang: privat per-user (sinkron antar device).
create table if not exists public.starred_messages (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  chat_type text not null check (chat_type in ('private', 'room')),
  chat_id text not null,
  message_id text not null,
  created_at timestamptz not null default now(),
  unique (user_id, chat_type, message_id)
);
create index if not exists idx_starred_user
  on public.starred_messages (user_id, created_at desc);

alter table public.starred_messages enable row level security;

drop policy if exists starred_messages_owner on public.starred_messages;
create policy starred_messages_owner on public.starred_messages
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Realtime untuk reaksi & bintang.
do $$
begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.starred_messages;
exception when duplicate_object then null;
end $$;
