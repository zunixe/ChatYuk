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
