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

-- 6. Tambahkan rooms ke realtime publication (fix bug sebelumnya)
alter publication supabase_realtime add table public.rooms;

-- 7. Hapus kolom ip_address dari profiles (privacy - GDPR/CCPA)
-- PERHATIAN: Jalankan ini hanya jika tidak ada dependency ke kolom ini
-- alter table public.profiles drop column if exists ip_address;
-- (Di-comment dulu, uncomment setelah dipastikan tidak dipakai)
