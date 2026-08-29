-- Timeline per-country shard — list_posts filter by country (tetap Supabase)
-- patch list_posts v4: tambah p_country param, filter posts.country = p_country jika not null
create or replace function public.list_posts(
  p_scope text default 'all',
  p_limit int default 30,
  p_cursor timestamptz default null,
  p_cursor_boosted boolean default false,
  p_country text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rows jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_scope not in ('all','following','mine') then p_scope := 'all'; end if;
  p_limit := least(coalesce(p_limit, 30), 50);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;

  with visible as (
    select p.*
    from public.posts p
    where
      (p_cursor is null
        or p.is_boosted < p_cursor_boosted
        or (p.is_boosted = p_cursor_boosted and p.created_at < p_cursor))
      and (p_country is null or p.country = p_country)
      and (
        p.visibility = 'public'
        or (p.visibility = 'followers' and (
              p.author_id = me
              or exists (select 1 from public.follows f where f.followee_id = p.author_id and f.follower_id = me)
              or exists (select 1 from public.subscriptions s where s.creator_id = p.author_id and s.subscriber_id = me and s.expires_at > now())
           ))
        or (p.visibility = 'subscribers' and (
              p.author_id = me
              or exists (select 1 from public.subscriptions s where s.creator_id = p.author_id and s.subscriber_id = me and s.expires_at > now())
           ))
      )
      and not exists (select 1 from public.blocks b
            where (b.blocker_id = me and b.blocked_id = p.author_id)
               or (b.blocker_id = p.author_id and b.blocked_id = me))
      and (
        p_scope = 'all'
        or (p_scope = 'mine' and p.author_id = me)
        or (p_scope = 'following' and (
              p.author_id = me
              or exists (select 1 from public.follows f where f.followee_id = p.author_id and f.follower_id = me)
           ))
      )
    order by p.is_boosted desc, p.created_at desc
    limit p_limit
  )
  select jsonb_agg(
    jsonb_build_object(
      'id', v.id,
      'authorId', v.author_id,
      'authorName', v.author_name,
      'authorGender', v.author_gender,
      'text', v.text,
      'imagePath', v.image_path,
      'visibility', v.visibility,
      'likeCount', v.like_count,
      'commentCount', v.comment_count,
      'shareCount', v.share_count,
      'isBoosted', v.is_boosted,
      'createdAt', v.created_at,
      'authorAvatar', pr.avatar,
      'isLiked', s.is_liked,
      'isFollowing', s.is_following,
      'isFriend', s.is_friend,
      'country', v.country
    )
    order by v.is_boosted desc, v.created_at desc
  )
  into rows
  from visible v
  left join public.profiles pr on pr.id = v.author_id
  left join lateral (
    select
      exists (select 1 from public.post_likes pl where pl.post_id = v.id and pl.user_id = me) as is_liked,
      exists (select 1 from public.follows f where f.followee_id = v.author_id and f.follower_id = me) as is_following,
      exists (
        select 1 from public.follows a
        join public.follows b on a.followee_id = b.follower_id and a.follower_id = b.followee_id
        where a.follower_id = me and a.followee_id = v.author_id) as is_friend
  ) s on true;

  return jsonb_build_object('posts', coalesce(rows, '[]'::jsonb));
end; $$;
-- keep old 4-param signature for backward compat
create or replace function public.list_posts(
  p_scope text, p_limit int, p_cursor timestamptz, p_cursor_boosted boolean
) returns jsonb language sql security definer set search_path=public as $$
  select public.list_posts(p_scope, p_limit, p_cursor, p_cursor_boosted, null::text);
$$;
revoke execute on function public.list_posts(text,int,timestamptz,boolean) from public, anon;
grant execute on function public.list_posts(text,int,timestamptz,boolean) to authenticated;
revoke execute on function public.list_posts(text,int,timestamptz,boolean,text) from public, anon;
grant execute on function public.list_posts(text,int,timestamptz,boolean,text) to authenticated;
