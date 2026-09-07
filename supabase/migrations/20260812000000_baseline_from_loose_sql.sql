-- ============================================================
-- BASELINE: rekonstruksi schema awal dari file loose (schema.sql,
-- schema_part2.sql, user_registered.sql, dll). Dibuat supaya
-- 'supabase db reset' bisa jalan dari nol. LIHAT MIGRATION_DISCIPLINE.md
-- ============================================================

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

-- ── BLOCKS (dipindah ke atas: dipakai policy private_messages) ──
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
          select p
          from public.private_chats pc2, unnest(pc2.participants) as p
          where pc2.chat_id = private_messages.chat_id
            and p != auth.uid()
          limit 1
        )
    )
  );

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

-- Enable realtime for presence & messages (idempotent — supabase_realtime
-- publication sudah ada di stack local)
do $$
begin
  alter publication supabase_realtime add table public.room_presence;
  alter publication supabase_realtime add table public.messages;
  alter publication supabase_realtime add table public.private_messages;
  alter publication supabase_realtime add table public.private_chats;
  alter publication supabase_realtime add table public.profiles;
exception
  when duplicate_object then null; -- tabel sudah member publication
end $$;

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

-- ===== schema_part2 =====

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

-- realtime publication (duplikat dari atas — dibuat idempotent)
do $$
begin
  alter publication supabase_realtime add table public.room_presence;
  alter publication supabase_realtime add table public.messages;
  alter publication supabase_realtime add table public.private_messages;
  alter publication supabase_realtime add table public.private_chats;
  alter publication supabase_realtime add table public.profiles;
exception
  when duplicate_object then null;
end $$;

insert into public.rooms (id, name, description, icon, "order") values ('general','General','Obrolan umum','💬',1),('curhat','Curhat','Cerita bareng','🤗',2),('pertemanan','Pertemanan','Cari teman','🤝',3),('teknologi','Teknologi','Diskusi tech','💻',4),('gaming','Gaming','Main bareng','🎮',5),('musik','Musik','Sharing musik','🎵',6),('film','Film & TV','Review film','🎬',7),('joke','Joke & Meme','Bikin ngakak','😂',8),('belajar','Belajar','Diskusi belajar','📚',9),('flirt','Flirt','Ngobrol asyik','😉',10) on conflict (id) do nothing;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values ('00000000-0000-0000-0000-000000000000','d1111111-0000-4000-8000-000000000001','authenticated','authenticated',null,'{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now()),('00000000-0000-0000-0000-000000000000','d2222222-0000-4000-8000-000000000002','authenticated','authenticated',null,'{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now()),('00000000-0000-0000-0000-000000000000','d3333333-0000-4000-8000-000000000003','authenticated','authenticated',null,'{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now()) on conflict (id) do nothing;

insert into public.profiles (id,nickname,gender,age,country,city,status) values ('d1111111-0000-4000-8000-000000000001','Budi','male',25,'Indonesia','Bandung','online'),('d2222222-0000-4000-8000-000000000002','Sari','female',21,'Indonesia','Surabaya','online'),('d3333333-0000-4000-8000-000000000003','Gamer','male',19,'Indonesia','Jakarta','online') on conflict (id) do update set status='online';

-- ===== user_photos =====

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
-- ===== rooms_country =====

-- ============================================
-- ChatYuk: Room per Negara
-- Tambah country/category, migrasi room lama ke Indonesia,
-- update referensi messages & room_presence.
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================

-- Lepas FK sementara agar bisa update id room
alter table public.messages drop constraint if exists messages_room_id_fkey;
alter table public.room_presence drop constraint if exists room_presence_room_id_fkey;

-- Kolom baru
alter table public.rooms add column if not exists country text not null default '';
alter table public.rooms add column if not exists category text not null default '';

-- Room lama dianggap milik Indonesia: category = id lama, id jadi 'Indonesia_<category>'
update public.rooms set category = id, country = 'Indonesia' where id not like 'Indonesia_%';
update public.messages set room_id = 'Indonesia_' || room_id where room_id not like 'Indonesia_%';
update public.room_presence set room_id = 'Indonesia_' || room_id where room_id not like 'Indonesia_%';
update public.rooms set id = 'Indonesia_' || id where id not like 'Indonesia_%';

-- Index untuk country
create index if not exists rooms_country_idx on public.rooms (country);

-- Pasang kembali FK
alter table public.messages add constraint messages_room_id_fkey
  foreign key (room_id) references public.rooms (id) on delete cascade;
alter table public.room_presence add constraint room_presence_room_id_fkey
  foreign key (room_id) references public.rooms (id) on delete cascade;
-- ===== rooms_rls_policy =====

-- ============================================
-- ChatYuk: Izinkan lazy-seed room per negara
-- Room di-seed otomatis oleh app (upsert) saat
-- negara baru dipilih. Perlu policy INSERT & UPDATE.
-- ============================================

drop policy if exists rooms_insert on public.rooms;
create policy rooms_insert on public.rooms
  for insert with check (true);

drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms
  for update using (true);
-- ===== notify_call_trigger =====

-- Trigger: kirim FCM push ke penerima saat ada panggilan masuk.
-- Supaya call tetap masuk walau aplikasi penerima force-stop / tertutup total.
-- Jalankan sekali di Supabase SQL Editor.

create or replace function public.notify_call() returns trigger as $$
declare
  receiver_token text;
  caller_name text;
  v_chat_id text;
begin
  -- Hanya kirim untuk status awal ringing (hindari dobel saat update).
  if new.status <> 'ringing' then
    return new;
  end if;

  select fcm_token into receiver_token
    from public.profiles where id = new.callee_id;
  select nickname into caller_name
    from public.profiles where id = new.caller_id;

  if receiver_token is null or receiver_token = '' then
    return new;
  end if;

  -- Format chat_id sama dengan client: uid disort lalu digabung '_'.
  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' ||
               greatest(new.caller_id::text, new.callee_id::text);

  begin
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', receiver_token,
        'data', jsonb_build_object(
          'type', 'call',
          'callId', new.id,
          'callerUid', new.caller_id,
          'callType', coalesce(new.call_type, 'video'),
          'chatId', v_chat_id,
          'otherName', coalesce(caller_name, 'User'),
          'fromName', coalesce(caller_name, 'User')
        )
      )
    );
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

-- ===== fixes =====

-- Cek apakah email sudah terdaftar di Auth (tanpa expose data user lain).
-- Dipanggil dari app sebelum mengirim email reset password.
-- Security definer + revoke dari public agar hanya mengembalikan boolean,
-- bukan data auth.users.
create or replace function public.check_email_registered(p_email text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from auth.users where lower(email) = lower(p_email)
  );
$$;

revoke all on function public.check_email_registered(p_email text) from public;
grant execute on function public.check_email_registered(p_email text) to anon, authenticated;

create or replace function public.notify_private_message() returns trigger as $$
declare
  receiver_id uuid;
  receiver_token text;
begin
  begin
    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is not null then
      select fcm_token into receiver_token from public.profiles where id = receiver_id;
      if receiver_token is not null and receiver_token <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json'),
          body := jsonb_build_object('token', receiver_token, 'title', new.sender_name, 'body', case when new.type = 'image' then '[Foto]' else new.text end, 'data', jsonb_build_object('chatId', new.chat_id, 'otherName', new.sender_name, 'otherUid', new.sender_id))
        );
      end if;
    end if;
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

create or replace function public.handle_new_private_message() returns trigger as $$
declare
  receiver uuid;
  unread jsonb := '{}'::jsonb;
  lastread jsonb := '{}'::jsonb;
begin
  select p2 into receiver from (
    select unnest(participants) as p2 from public.private_chats where chat_id = new.chat_id
  ) x where p2 <> new.sender_id limit 1;
  if receiver is null then return new; end if;

  select coalesce(unread_counts, '{}'::jsonb) into unread from public.private_chats where chat_id = new.chat_id;
  if unread is null then unread := '{}'::jsonb; end if;
  unread := jsonb_set(unread, array[receiver::text], to_jsonb(coalesce((unread->>receiver::text)::int, 0) + 1), true);

  select coalesce(last_read_at, '{}'::jsonb) into lastread from public.private_chats where chat_id = new.chat_id;
  if lastread is null then lastread := '{}'::jsonb; end if;

  update public.private_chats set
    last_message = case when new.type = 'image' then '[Foto]' else new.text end,
    last_message_at = now(),
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $$ language plpgsql security definer;

-- ============================================================
-- ChatYuk: Fix view-once photo expired
-- private_messages hanya punya policy SELECT + INSERT.
-- clearViewOnceImage() meng-update row (hapus image_data + ubah type),
-- tapi ditolak RLS karena tidak ada policy UPDATE.
-- Akibatnya foto view-once tidak pernah benar-benar dihapus dari DB,
-- sehingga setelah keluar-masuk chat foto bisa dilihat lagi.
--
-- Jalankan di: Supabase Dashboard > SQL Editor > Run
-- Catatan: JANGAN pakai `new.` di with check — error 42P01.
--         Pakai referensi kolom langsung (type, image_data).
-- ============================================================

drop policy if exists "private_messages_update_view_once" on public.private_messages;

create policy "private_messages_update_view_once" on public.private_messages
  for update
  using (
    -- Hanya peserta chat yang bisa meng-update pesan di chat-nya
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
  )
  with check (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Batasi: update hanya boleh menghasilkan pesan view_once expired tanpa foto
    and type = 'view_once_expired'
    and image_data = ''
  );

-- Fix RLS private_messages untuk blokir
-- Jalankan di Supabase Dashboard → SQL Editor

-- 1. Hapus policy lama
drop policy if exists "private_messages_select" on public.private_messages;
drop policy if exists "private_messages_insert" on public.private_messages;

-- 2. SELECT: sembunyikan pesan dari orang yang diblokir oleh penerima
create policy "private_messages_select" on public.private_messages
  for select using (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Sembunyikan pesan dari orang yang saya blokir
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid()
        and b.blocked_id = private_messages.sender_id
    )
  );

-- 3. INSERT: tolak pesan jika pengirim diblokir oleh penerima
create policy "private_messages_insert" on public.private_messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Tolak jika pengirim diblokir oleh salah satu peserta lain
    and not exists (
      select 1 from public.blocks b
      join public.private_chats pc on pc.chat_id = private_messages.chat_id
      where b.blocked_id = auth.uid()
        and b.blocker_id = any (pc.participants)
        and b.blocker_id != auth.uid()
    )
  );

-- ============================================================
-- ChatYuk Security Fixes
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================================

-- 1. Constraint tipe pesan valid (mencegah tipe sembarangan masuk DB)
alter table public.messages
  drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check
  check (type in ('text', 'image', 'view_once', 'view_once_expired'));

alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check
  check (type in ('text', 'image', 'view_once', 'view_once_expired'));

-- 2. Panjang teks pesan maksimal 2000 karakter
alter table public.messages
  drop constraint if exists messages_text_length;
alter table public.messages
  add constraint messages_text_length
  check (length(text) <= 2000);

alter table public.private_messages
  drop constraint if exists private_messages_text_length;
alter table public.private_messages
  add constraint private_messages_text_length
  check (length(text) <= 2000);

-- 3. Nickname harus unik
alter table public.profiles
  drop constraint if exists profiles_nickname_unique;
alter table public.profiles
  add constraint profiles_nickname_unique unique (nickname);

-- 4. Nickname tidak boleh kosong atau terlalu panjang
alter table public.profiles
  drop constraint if exists profiles_nickname_length;
alter table public.profiles
  add constraint profiles_nickname_length
  check (length(trim(nickname)) >= 3 and length(nickname) <= 20);

-- 5. Trigger: auto-set sender_name dari profiles saat insert pesan
-- (mencegah user kirim pesan dengan nama orang lain)
create or replace function public.set_sender_name_from_profile()
returns trigger as $$
declare
  profile_nickname text;
  profile_gender text;
begin
  select nickname, gender into profile_nickname, profile_gender
  from public.profiles
  where id = new.sender_id;

  if profile_nickname is not null then
    new.sender_name := profile_nickname;
    new.sender_gender := profile_gender;
  end if;
  return new;
end;
$$ language plpgsql security definer;

-- Apply trigger ke messages
drop trigger if exists set_sender_name_messages on public.messages;
create trigger set_sender_name_messages
  before insert on public.messages
  for each row execute function public.set_sender_name_from_profile();

-- Apply trigger ke private_messages
drop trigger if exists set_sender_name_private_messages on public.private_messages;
create trigger set_sender_name_private_messages
  before insert on public.private_messages
  for each row execute function public.set_sender_name_from_profile();

-- 6. Tambahkan rooms ke realtime publication (fix bug sebelumnya, idempotent)
do $$
begin
  alter publication supabase_realtime add table public.rooms;
exception
  when duplicate_object then null;
end $$;

-- 7. Hapus kolom ip_address dari profiles (privacy - GDPR/CCPA)
-- PERHATIAN: Jalankan ini hanya jika tidak ada dependency ke kolom ini
-- alter table public.profiles drop column if exists ip_address;
-- (Di-comment dulu, uncomment setelah dipastikan tidak dipakai)

-- ============================================================
-- ChatYuk Security Fixes v2
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================================

-- ── FIX 1: profiles_update_own — tambah with check ──
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id)
  with check (
    auth.uid() = id
    and status in ('online', 'idle', 'offline')
    and length(trim(nickname)) >= 3
    and length(nickname) <= 20
  );

-- ── FIX 2: private_chats_insert — validasi kedua participant harus ada ──
drop policy if exists "private_chats_insert" on public.private_chats;
create policy "private_chats_insert" on public.private_chats
  for insert with check (
    auth.uid() = any (participants)
    and array_length(participants, 1) = 2
    and participants[1] != participants[2]
    and exists (select 1 from public.profiles where id = participants[1])
    and exists (select 1 from public.profiles where id = participants[2])
  );

-- ── FIX 3: blocks — tidak boleh blokir diri sendiri ──
drop policy if exists "blocks_insert_own" on public.blocks;
create policy "blocks_insert_own" on public.blocks
  for insert with check (
    auth.uid() = blocker_id
    and blocker_id != blocked_id
  );

-- ── FIX 4: Avatar size limit ──
alter table public.profiles
  drop constraint if exists profiles_avatar_size;
alter table public.profiles
  add constraint profiles_avatar_size
  check (length(avatar) <= 524288); -- 512KB base64

-- ── FIX 5: Trigger auto-set nickname di room_presence dari profiles ──
create or replace function public.set_room_presence_from_profile()
returns trigger as $$
declare
  profile_nickname text;
  profile_gender text;
  profile_age int;
begin
  select nickname, gender, age
  into profile_nickname, profile_gender, profile_age
  from public.profiles
  where id = new.user_id;

  if profile_nickname is not null then
    new.nickname := profile_nickname;
    new.gender := coalesce(profile_gender, 'other');
    new.age := coalesce(profile_age, 0);
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists set_room_presence_trigger on public.room_presence;
create trigger set_room_presence_trigger
  before insert or update on public.room_presence
  for each row execute function public.set_room_presence_from_profile();

-- ── FIX 6: private_chats_update — batasi field yang bisa di-update ──
-- Hanya boleh update unread_counts dan last_read_at milik sendiri
-- (implementasi via trigger lebih proper)
create or replace function public.check_private_chat_update()
returns trigger as $$
begin
  -- Hanya participant yang boleh update
  if not (auth.uid() = any (new.participants)) then
    raise exception 'Not authorized';
  end if;
  -- Participant tidak boleh diubah setelah dibuat
  if new.participants != old.participants then
    raise exception 'Cannot modify participants';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists check_private_chat_update_trigger on public.private_chats;
create trigger check_private_chat_update_trigger
  before update on public.private_chats
  for each row execute function public.check_private_chat_update();

-- ── FIX 7: Tambah reports_select untuk admin (service role) ──
-- Policy ini hanya accessible via service role key (admin), bukan anon key
-- Untuk sekarang cukup biarkan tanpa select policy (data laporan tidak bisa dibaca user biasa)
-- Jika perlu admin dashboard, buat via service role

-- ── FIX 8: Constraint status profile valid ──
alter table public.profiles
  drop constraint if exists profiles_status_check;
alter table public.profiles
  add constraint profiles_status_check
  check (status in ('online', 'idle', 'offline'));

-- ── FIX 9: Constraint gender valid ──
alter table public.profiles
  drop constraint if exists profiles_gender_check;
alter table public.profiles
  add constraint profiles_gender_check
  check (gender in ('male', 'female', 'other'));

alter table public.messages
  drop constraint if exists messages_gender_check;
alter table public.messages
  add constraint messages_gender_check
  check (sender_gender in ('male', 'female', 'other'));

alter table public.private_messages
  drop constraint if exists private_messages_gender_check;
alter table public.private_messages
  add constraint private_messages_gender_check
  check (sender_gender in ('male', 'female', 'other'));

-- ── FIX 10: Age constraint ──
alter table public.profiles
  drop constraint if exists profiles_age_check;
alter table public.profiles
  add constraint profiles_age_check
  check (age >= 0 and age <= 120);

-- ===== cleanup_stale_anonymous =====

-- Hapus akun anonymous yang sudah tidak aktif (stale) agar
-- username/nickname mereka bebas dipakai lagi dan tidak
-- muncul sebagai "online" ghost di daftar pengguna.
-- Panggil dari app saat start (fire-and-forget).

create or replace function public.cleanup_stale_anonymous(min_age_days int default 7)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted int := 0;
  r record;
begin
  -- Akun anonymous (tanpa email) yang last_seen lebih lama dari threshold.
  -- Anonymous tidak bisa login ulang → aman dihapus.
  for r in
    select u.id
    from auth.users u
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.profiles p
        where p.id = u.id
          and p.last_seen > now() - make_interval(days => min_age_days)
      )
  loop
    -- Hapus data yang melibatkan user ini
    delete from public.room_presence where user_id = r.id;
    delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
    delete from public.reports where reporter_id = r.id or reported_id = r.id;
    delete from public.user_photos where user_id = r.id;

    -- Private chats yang hanya melibatkan user ini (2 pihak, keduanya stale)
    delete from public.private_messages pm
    using public.private_chats pc
    where pm.chat_id = pc.chat_id
      and pc.participants @> array[r.id]::uuid[];

    delete from public.private_chats pc
    where pc.participants @> array[r.id]::uuid[];

    -- Private messages yang dikirim user (chat mungkin sudah dihapus di atas)
    delete from public.private_messages where sender_id = r.id;

    delete from public.profiles where id = r.id;
    delete from auth.users where id = r.id;
    deleted := deleted + 1;
  end loop;
  return deleted;
end;
$$;

revoke execute on function public.cleanup_stale_anonymous(int) from public, anon;
grant execute on function public.cleanup_stale_anonymous(int) to authenticated, service_role;

-- ===== user_registered (terlewat dari concat awal) =====
-- ============================================
-- ChatYuk: Tandai user terdaftar (registered)
-- Kolom is_registered di profiles, messages, room_presence,
-- dan participant_registered di private_chats.
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================

-- ── 1. Kolom baru ──
alter table public.profiles add column if not exists is_registered boolean not null default false;
alter table public.messages add column if not exists is_registered boolean not null default false;
alter table public.private_messages add column if not exists is_registered boolean not null default false;
alter table public.room_presence add column if not exists is_registered boolean not null default false;
alter table public.private_chats add column if not exists participant_registered jsonb not null default '{}';

-- ── 2. Backfill: user yang punya email = registered ──
update public.profiles p
set is_registered = exists (
  select 1 from auth.users u where u.id = p.id and u.email is not null and u.email <> ''
);

-- ── 3. Trigger messages: copy is_registered dari profiles ──
create or replace function public.set_sender_name_from_profile()
returns trigger as $$
declare
  profile_nickname text;
  profile_gender text;
  profile_registered boolean;
begin
  select nickname, gender, is_registered into profile_nickname, profile_gender, profile_registered
  from public.profiles where id = new.sender_id;
  if profile_nickname is not null then
    new.sender_name := profile_nickname;
  end if;
  if profile_gender is not null then
    new.sender_gender := profile_gender;
  end if;
  if profile_registered is not null then
    new.is_registered := profile_registered;
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists set_sender_name_messages on public.messages;
create trigger set_sender_name_messages
  before insert on public.messages
  for each row execute function public.set_sender_name_from_profile();

drop trigger if exists set_sender_name_private_messages on public.private_messages;
create trigger set_sender_name_private_messages
  before insert on public.private_messages
  for each row execute function public.set_sender_name_from_profile();

-- ── 4. Trigger room_presence: copy is_registered dari profiles ──
create or replace function public.set_room_presence_from_profile()
returns trigger as $$
declare
  profile_nickname text;
  profile_gender text;
  profile_registered boolean;
begin
  select nickname, gender, is_registered into profile_nickname, profile_gender, profile_registered
  from public.profiles where id = new.user_id;
  if profile_nickname is not null then
    new.nickname := profile_nickname;
  end if;
  if profile_gender is not null then
    new.gender := profile_gender;
  end if;
  if profile_registered is not null then
    new.is_registered := profile_registered;
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists set_room_presence_trigger on public.room_presence;
create trigger set_room_presence_trigger
  before insert or update on public.room_presence
  for each row execute function public.set_room_presence_from_profile();

-- ── 5. Trigger private_chats: set participant_registered dari profiles ──
create or replace function public.set_participant_registered()
returns trigger as $$
declare
  rec record;
begin
  new.participant_registered := '{}'::jsonb;
  for rec in
    select id, is_registered from public.profiles where id = any(new.participants)
  loop
    new.participant_registered := new.participant_registered || jsonb_build_object(rec.id::text, rec.is_registered);
  end loop;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists set_participant_registered_trigger on public.private_chats;
create trigger set_participant_registered_trigger
  before insert on public.private_chats
  for each row execute function public.set_participant_registered();

-- ── 6. Backfill private_chats yang sudah ada ──
update public.private_chats pc
set participant_registered = (
  select coalesce(jsonb_object_agg(p.id::text, p.is_registered), '{}'::jsonb)
  from public.profiles p where p.id = any(pc.participants)
);