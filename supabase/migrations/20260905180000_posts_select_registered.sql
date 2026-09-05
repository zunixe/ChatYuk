-- posts_select: anon TIDAK pernah bisa baca posts (timeline registered-only,
-- absolut). Menutup bocor realtime postgres_changes (RLS menyaring payload)
-- plus select langsung. Bypass: dummy & admin. list_posts (security
-- definer) sudah punya guard sendiri.
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select using (
  not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  )
  and (
    visibility = 'public'
    or (visibility = 'followers' and (
          author_id = auth.uid()
          or exists (select 1 from follows f where f.followee_id = posts.author_id and f.follower_id = auth.uid())
          or exists (select 1 from subscriptions s where s.creator_id = posts.author_id and s.subscriber_id = auth.uid() and s.expires_at > now())
       ))
    or (visibility = 'subscribers' and (
          author_id = auth.uid()
          or exists (select 1 from subscriptions s where s.creator_id = posts.author_id and s.subscriber_id = auth.uid() and s.expires_at > now())
       ) and not exists (
          select 1 from blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = posts.author_id)
             or (b.blocker_id = posts.author_id and b.blocked_id = auth.uid())
       ))
  )
);
