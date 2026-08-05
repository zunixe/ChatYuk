-- Lanjutan schema (profiles sudah ada)
create table if not exists public.rooms (id text primary key, name text not null, description text not null default '', icon text not null default '💬', "order" int not null default 0);
alter table public.rooms enable row level security;
drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms for select using (true);

create table if not exists public.messages (id bigint generated always as identity primary key, room_id text not null references public.rooms(id) on delete cascade, sender_id uuid not null, sender_name text not null default 'Anon', sender_gender text not null default 'other', text text not null default '', type text not null default 'text', image_data text not null default '', created_at timestamptz not null default now());
create index if not exists messages_room_created_idx on public.messages (room_id, created_at desc);
alter table public.messages enable row level security;
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages for select using (true);
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert with check (auth.uid() = sender_id);

create table if not exists public.private_chats (chat_id text primary key, participants uuid[] not null, participant_names jsonb not null default '{}', participant_genders jsonb not null default '{}', participant_locations jsonb not null default '{}', participant_ages jsonb not null default '{}', last_message text not null default '', last_message_at timestamptz not null default now(), unread_counts jsonb not null default '{}', last_read_at jsonb not null default '{}');
alter table public.private_chats enable row level security;
drop policy if exists private_chats_select on public.private_chats;
create policy private_chats_select on public.private_chats for select using (auth.uid() = any(participants));
drop policy if exists private_chats_insert on public.private_chats;
create policy private_chats_insert on public.private_chats for insert with check (auth.uid() = any(participants));
drop policy if exists private_chats_update on public.private_chats;
create policy private_chats_update on public.private_chats for update using (auth.uid() = any(participants));

create table if not exists public.private_messages (id bigint generated always as identity primary key, chat_id text not null references public.private_chats(chat_id) on delete cascade, sender_id uuid not null, sender_name text not null default 'Anon', sender_gender text not null default 'other', text text not null default '', type text not null default 'text', image_data text not null default '', created_at timestamptz not null default now());
create index if not exists private_messages_chat_created_idx on public.private_messages (chat_id, created_at desc);
alter table public.private_messages enable row level security;
drop policy if exists private_messages_select on public.private_messages;
create policy private_messages_select on public.private_messages for select using (exists (select 1 from public.private_chats pc where pc.chat_id = private_messages.chat_id and auth.uid() = any(pc.participants)));
drop policy if exists private_messages_insert on public.private_messages;
create policy private_messages_insert on public.private_messages for insert with check (auth.uid() = sender_id and exists (select 1 from public.private_chats pc where pc.chat_id = private_messages.chat_id and auth.uid() = any(pc.participants)));

create table if not exists public.blocks (blocker_id uuid not null, blocked_id uuid not null, blocked_at timestamptz not null default now(), primary key (blocker_id, blocked_id));
alter table public.blocks enable row level security;
drop policy if exists blocks_select_own on public.blocks;
create policy blocks_select_own on public.blocks for select using (auth.uid() = blocker_id);
drop policy if exists blocks_insert_own on public.blocks;
create policy blocks_insert_own on public.blocks for insert with check (auth.uid() = blocker_id);
drop policy if exists blocks_delete_own on public.blocks;
create policy blocks_delete_own on public.blocks for delete using (auth.uid() = blocker_id);

create table if not exists public.reports (id bigint generated always as identity primary key, reporter_id uuid not null, reported_id uuid not null, reason text not null default '', created_at timestamptz not null default now());
alter table public.reports enable row level security;
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports for insert with check (auth.uid() = reporter_id);

create table if not exists public.room_presence (room_id text not null references public.rooms(id) on delete cascade, user_id uuid not null, nickname text not null default 'Anon', gender text not null default 'other', age int not null default 0, joined_at timestamptz not null default now(), primary key (room_id, user_id));
alter table public.room_presence enable row level security;
drop policy if exists room_presence_select on public.room_presence;
create policy room_presence_select on public.room_presence for select using (true);
drop policy if exists room_presence_insert_own on public.room_presence;
create policy room_presence_insert_own on public.room_presence for insert with check (auth.uid() = user_id);
drop policy if exists room_presence_delete_own on public.room_presence;
create policy room_presence_delete_own on public.room_presence for delete using (auth.uid() = user_id);
drop policy if exists room_presence_update_own on public.room_presence;
create policy room_presence_update_own on public.room_presence for update using (auth.uid() = user_id);

alter publication supabase_realtime add table public.room_presence;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.private_messages;
alter publication supabase_realtime add table public.private_chats;
alter publication supabase_realtime add table public.profiles;

insert into public.rooms (id, name, description, icon, "order") values ('general','General','Obrolan umum','💬',1),('curhat','Curhat','Cerita bareng','🤗',2),('pertemanan','Pertemanan','Cari teman','🤝',3),('teknologi','Teknologi','Diskusi tech','💻',4),('gaming','Gaming','Main bareng','🎮',5),('musik','Musik','Sharing musik','🎵',6),('film','Film & TV','Review film','🎬',7),('joke','Joke & Meme','Bikin ngakak','😂',8),('belajar','Belajar','Diskusi belajar','📚',9),('flirt','Flirt','Ngobrol asyik','😉',10) on conflict (id) do nothing;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values ('00000000-0000-0000-0000-000000000000','d1111111-0000-4000-8000-000000000001','authenticated','authenticated',null,'{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now()),('00000000-0000-0000-0000-000000000000','d2222222-0000-4000-8000-000000000002','authenticated','authenticated',null,'{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now()),('00000000-0000-0000-0000-000000000000','d3333333-0000-4000-8000-000000000003','authenticated','authenticated',null,'{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now()) on conflict (id) do nothing;

insert into public.profiles (id,nickname,gender,age,country,city,status) values ('d1111111-0000-4000-8000-000000000001','Budi','male',25,'Indonesia','Bandung','online'),('d2222222-0000-4000-8000-000000000002','Sari','female',21,'Indonesia','Surabaya','online'),('d3333333-0000-4000-8000-000000000003','Gamer','male',19,'Indonesia','Jakarta','online') on conflict (id) do update set status='online';
