-- ============================================================
-- ChatYuk: Realtime sosial — friends_count + publication
--
-- - Tambah kolom profiles.friends_count (denormalized, mutual follow).
-- - Rewrite trigger follow_count_sync supaya ikut memelihara friends_count
--   saat dua user saling follow (friend) / unfollow.
-- - Tambah tabel sosial ke realtime publication supaya counter & daftar
--   pengikut/mengikuti/teman update realtime di kedua sisi.
-- ============================================================

alter table public.profiles
  add column if not exists friends_count int not null default 0;

-- Isi awal friends_count dari relasi mutual yang sudah ada (idempoten).
update public.profiles p
set friends_count = coalesce((
  select count(*)
  from public.follows a
  join public.follows b
    on a.followee_id = b.follower_id
   and a.follower_id = b.followee_id
  where a.follower_id = p.id
), 0);

create or replace function public.follow_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update profiles set followers_count = followers_count + 1
      where id = new.followee_id;
    update profiles set following_count = following_count + 1
      where id = new.follower_id;
    -- Jadi teman bila followee juga mengikuti follower (mutual).
    if exists (select 1 from follows where follower_id = new.followee_id
               and followee_id = new.follower_id) then
      update profiles set friends_count = friends_count + 1
        where id in (new.follower_id, new.followee_id);
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    update profiles set followers_count = greatest(followers_count - 1, 0)
      where id = old.followee_id;
    update profiles set following_count = greatest(following_count - 1, 0)
      where id = old.follower_id;
    -- Bukan teman lagi bila sebelumnya saling follow.
    if exists (select 1 from follows where follower_id = old.followee_id
               and followee_id = old.follower_id) then
      update profiles set friends_count = greatest(friends_count - 1, 0)
        where id in (old.follower_id, old.followee_id);
    end if;
    return old;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists follow_count_trigger on public.follows;
create trigger follow_count_trigger after insert or delete on public.follows
  for each row execute function public.follow_count_sync();

-- Realtime: tabel sosial ikut di-publish supaya event sampai ke client.
alter publication supabase_realtime add table public.follows;
alter publication supabase_realtime add table public.friend_requests;
alter publication supabase_realtime add table public.subscriptions;
