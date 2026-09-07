-- ============================================================
-- ChatYuk: counter sosial = semantik social_list (join profiles)
--
-- Latar: counter Pengikut SimpleMe = 2 padahal list saat diklik = 1.
-- Penyebab: baris follows ORPHAN (profil follower sudah terhapus) tetap
-- terhitung oleh follow_count_sync, sedangkan social_list() inner-join
-- profiles sehingga baris orphan tidak tampil di list. FK cascade
-- seharusnya menghapus baris follows saat profil dihapus, tapi data
-- live membuktikan orphan tetap ada (riwayat hapus manual / pra-FK).
--
-- Fix:
-- 1. Hapus baris follows orphan (profil sisi manapun sudah tiada).
-- 2. follow_count_sync hitung HANYA follows yang kedua profilnya ada
--    (join profiles) — persis semantik social_list. Drift orphan
--    tidak mungkin menetap.
-- 3. Backfill sekali untuk semua profile (idempoten).
-- ============================================================

-- 1. Bersihkan orphan (pemicu trigger AFTER DELETE → recount otomatis
--    untuk sisi yang masih ada).
delete from public.follows f
where not exists (select 1 from public.profiles p where p.id = f.follower_id)
   or not exists (select 1 from public.profiles p where p.id = f.followee_id);

-- 2. Trigger full recount — join profiles agar identik social_list.
create or replace function public.follow_count_sync() returns trigger as $$
begin
  update public.profiles p
  set
    followers_count = (
      select count(*) from public.follows f
      join public.profiles fp on fp.id = f.follower_id
      where f.followee_id = p.id and f.follower_id <> p.id
    ),
    following_count = (
      select count(*) from public.follows f
      join public.profiles fe on fe.id = f.followee_id
      where f.follower_id = p.id and f.followee_id <> p.id
    ),
    friends_count = (
      select count(*) from public.follows a
      join public.follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join public.profiles pa on pa.id = a.follower_id
      join public.profiles pb on pb.id = a.followee_id
      where a.follower_id = p.id and a.followee_id <> p.id
    )
  where p.id in (
    coalesce(new.follower_id, old.follower_id),
    coalesce(new.followee_id, old.followee_id)
  );
  return null; -- AFTER trigger, return value diabaikan
end; $$ language plpgsql security definer;

-- 3. Backfill sekali — semantik sama dengan trigger & social_list.
update public.profiles p
set
  followers_count = coalesce((
    select count(*) from public.follows f
    join public.profiles fp on fp.id = f.follower_id
    where f.followee_id = p.id and f.follower_id <> p.id
  ), 0),
  following_count = coalesce((
    select count(*) from public.follows f
    join public.profiles fe on fe.id = f.followee_id
    where f.follower_id = p.id and f.followee_id <> p.id
  ), 0),
  friends_count = coalesce((
    select count(*) from public.follows a
    join public.follows b
      on a.followee_id = b.follower_id and a.follower_id = b.followee_id
    join public.profiles pa on pa.id = a.follower_id
    join public.profiles pb on pb.id = a.followee_id
    where a.follower_id = p.id and a.followee_id <> p.id
  ), 0);
