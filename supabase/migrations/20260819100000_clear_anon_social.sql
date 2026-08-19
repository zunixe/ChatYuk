-- ============================================================
-- ChatYuk: Hapus relasi sosial user anon saat logout.
-- Anon boleh follow/subscribe, tapi begitu logout relasinya dihapus
-- sehingga followers_count / subscriber_count user lain ikut berkurang
-- (otomatis lewat trigger exists di tabel follows & subscriptions).
-- ============================================================

create or replace function public.clear_anon_social()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.follows
  where follower_id = auth.uid();
  delete from public.subscriptions
  where subscriber_id = auth.uid();
  delete from public.friend_requests
  where from_id = auth.uid();
end;
$$;

revoke all on function public.clear_anon_social() from public;
grant execute on function public.clear_anon_social() to anon;
