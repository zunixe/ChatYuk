-- ============================================================
-- ChatYuk: Reconcile counter sosial dari tabel follows (source of truth)
--
-- followers_count/following_count/friends_count kadang drift karena
-- di-backfill saat kondisi berbeda lalu event follow/unfollow terjadi
-- sebelum trigger yang maintain friends_count terpasang.
-- Migration ini menghitung ulang semua counter dari follows — idempoten,
-- aman dijalankan ulang kapan pun untuk memperbaiki data.
-- ============================================================

-- followers_count: jumlah orang yang follow saya
update public.profiles p
set followers_count = coalesce((
  select count(*) from public.follows f where f.followee_id = p.id
), 0);

-- following_count: jumlah orang yang saya follow
update public.profiles p
set following_count = coalesce((
  select count(*) from public.follows f where f.follower_id = p.id
), 0);

-- friends_count: jumlah mutual follow (saling follow)
update public.profiles p
set friends_count = coalesce((
  select count(*)
  from public.follows a
  join public.follows b
    on a.follower_id = b.followee_id
   and a.followee_id = b.follower_id
  where a.follower_id = p.id
), 0);

-- RPC maintenance: hitung ulang counter sosial (dipanggil admin/bila drift).
create or replace function public.recount_social_counts()
returns jsonb language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  update public.profiles p
  set followers_count = coalesce((select count(*) from public.follows f where f.followee_id = p.id), 0);
  get diagnostics tot = row_count;

  update public.profiles p
  set following_count = coalesce((select count(*) from public.follows f where f.follower_id = p.id), 0);

  update public.profiles p
  set friends_count = coalesce((
    select count(*)
    from public.follows a
    join public.follows b
      on a.follower_id = b.followee_id
     and a.followee_id = b.follower_id
    where a.follower_id = p.id
  ), 0);

  return jsonb_build_object('ok', true, 'profiles_recounted', tot);
end; $$;
revoke execute on function public.recount_social_counts() from public, anon;
grant execute on function public.recount_social_counts() to authenticated, service_role;
