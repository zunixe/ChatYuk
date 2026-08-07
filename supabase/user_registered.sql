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