-- Sync nickname/gender/age/country ke private_chats saat profil berubah
-- Fix: chat list menampilkan "tes" padahal profil sudah "malamputih"
create or replace function public.sync_profile_to_chats() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.nickname is distinct from old.nickname then
    update private_chats set participant_names = jsonb_set(participant_names, array[new.id::text], to_jsonb(new.nickname))
    where participant_names ? new.id::text;
  end if;
  if new.gender is distinct from old.gender then
    update private_chats set participant_genders = jsonb_set(participant_genders, array[new.id::text], to_jsonb(new.gender))
    where participant_genders ? new.id::text;
  end if;
  if new.age is distinct from old.age then
    update private_chats set participant_ages = jsonb_set(participant_ages, array[new.id::text], to_jsonb(new.age))
    where participant_ages ? new.id::text;
  end if;
  if new.country is distinct from old.country then
    update private_chats set participant_locations = jsonb_set(participant_locations, array[new.id::text], to_jsonb(new.country))
    where participant_locations ? new.id::text;
  end if;
  return new;
end; $$;

drop trigger if exists trg_sync_profile_to_chats on profiles;
create trigger trg_sync_profile_to_chats after update of nickname, gender, age, country on profiles
for each row execute function sync_profile_to_chats();
