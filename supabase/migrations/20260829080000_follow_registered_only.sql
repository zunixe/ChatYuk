-- Hanya user terdaftar (is_registered=true) yang bisa saling follow
-- Anon (guest) tidak bisa follow & tidak bisa difollow
drop policy if exists follows_insert_own on public.follows;
create policy follows_insert_own on public.follows for insert
with check (
  auth.uid() = follower_id
  and exists (select 1 from public.profiles p where p.id = follower_id and p.is_registered = true)
  and exists (select 1 from public.profiles p where p.id = followee_id and p.is_registered = true)
);

-- Friend request juga hanya untuk registered
drop policy if exists friend_requests_insert_own on public.friend_requests;
create policy friend_requests_insert_own on public.friend_requests for insert
with check (
  auth.uid() = from_id
  and exists (select 1 from public.profiles p where p.id = from_id and p.is_registered = true)
  and exists (select 1 from public.profiles p where p.id = to_id and p.is_registered = true)
);
