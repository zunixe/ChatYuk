-- ============================================================
-- ChatYuk: anti-drift counter sosial
--
-- Latar: friends_count bisa drift ke atas (contoh: akun 'playwright'
-- friends_count=3 padahal following=1/followers=1 — mustahil untuk
-- mutual follow). Penyebab: increment/decrement inkremental di trigger
-- lama tidak self-healing; satu kejadian aneh (delete langsung, race,
-- data pra-trigger) membuat selisih menetap selamanya.
--
-- Fix:
-- 1. follow_count_sync di-rewrite jadi FULL RECOUNT per user terdampak
--    (selalu cocok dengan query social_list — join profiles, tanpa
--    self-follow). Drift tidak mungkin menetap.
-- 2. Backfill sekali untuk semua profile (idempoten).
-- ============================================================

create or replace function public.follow_count_sync() returns trigger as $$
begin
  update public.profiles p
  set
    followers_count = (
      select count(*) from public.follows f
      where f.followee_id = p.id and f.follower_id <> p.id
    ),
    following_count = (
      select count(*) from public.follows f
      where f.follower_id = p.id and f.followee_id <> p.id
    ),
    friends_count = (
      select count(*) from public.follows a
      join public.follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      where a.follower_id = p.id and a.followee_id <> p.id
    )
  where p.id in (
    coalesce(new.follower_id, old.follower_id),
    coalesce(new.followee_id, old.followee_id)
  );
  return null; -- AFTER trigger, return value diabaikan
end; $$ language plpgsql security definer;

drop trigger if exists follow_count_trigger on public.follows;
create trigger follow_count_trigger
after insert or delete on public.follows
for each row execute function public.follow_count_sync();

-- Backfill sekali — samakan persis dengan semantik social_list
-- (mutual follow, join profiles implisit lewat FK cascade, tanpa self).
update public.profiles p
set
  followers_count = coalesce((
    select count(*) from public.follows f
    where f.followee_id = p.id and f.follower_id <> p.id
  ), 0),
  following_count = coalesce((
    select count(*) from public.follows f
    where f.follower_id = p.id and f.followee_id <> p.id
  ), 0),
  friends_count = coalesce((
    select count(*) from public.follows a
    join public.follows b
      on a.followee_id = b.follower_id and a.follower_id = b.followee_id
    where a.follower_id = p.id and a.followee_id <> p.id
  ), 0);
