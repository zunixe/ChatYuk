-- Sync nickname ke semua tabel snapshot saat profil berubah.
-- Fix: user ganti username, tapi post/komen/story lama masih menampilkan
-- nama lama (snapshot tidak pernah di-update).
-- Pola sama dengan sync_profile_to_chats (20260828050000).

create or replace function public.sync_profile_names() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.nickname is distinct from old.nickname then
    update public.posts
       set author_name = new.nickname
     where author_id = new.id
       and author_name is distinct from new.nickname;

    update public.post_comments
       set author_name = new.nickname
     where author_id = new.id
       and author_name is distinct from new.nickname;

    update public.stories
       set author_name = new.nickname
     where author_id = new.id
       and author_name is distinct from new.nickname;

    update public.user_devices
       set nickname_snapshot = new.nickname
     where user_id = new.id
       and nickname_snapshot is distinct from new.nickname;
  end if;
  return new;
end; $$;

drop trigger if exists trg_sync_profile_names on public.profiles;
create trigger trg_sync_profile_names
  after update of nickname on public.profiles
  for each row execute function public.sync_profile_names();

-- Backfill: samakan snapshot lama dengan nickname sekarang (satu kali).
update public.posts p
   set author_name = pr.nickname
  from public.profiles pr
 where pr.id = p.author_id
   and p.author_name is distinct from pr.nickname;

update public.post_comments pc
   set author_name = pr.nickname
  from public.profiles pr
 where pr.id = pc.author_id
   and pc.author_name is distinct from pr.nickname;

update public.stories st
   set author_name = pr.nickname
  from public.profiles pr
 where pr.id = st.author_id
   and st.author_name is distinct from pr.nickname;

update public.user_devices ud
   set nickname_snapshot = pr.nickname
  from public.profiles pr
 where pr.id = ud.user_id
   and ud.nickname_snapshot is distinct from pr.nickname;
