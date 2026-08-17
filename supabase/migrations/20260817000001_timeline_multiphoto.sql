-- ============================================================
-- ChatYuk Timeline — Multi-foto untuk post
-- - Kolom baru posts.images text[] (daftar path storage).
-- - create_post menerima p_image_paths text[] (menggantikan image_path).
-- - list_posts mengembalikan images[].
-- ============================================================

alter table public.posts
  add column if not exists images text[] not null default '{}';

-- RPC create_post — terima array path foto (multi-foto).
-- Kompatibel dengan panggilan lama p_image_path (disimpan ke images[0]).
create or replace function public.create_post(
  p_text text default '',
  p_image_paths text[] default '{}',
  p_visibility text default 'public'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  am_registered boolean; my_name text; my_gender text;
  daily_lim int; today_count int; new_id uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_visibility not in ('public','followers','subscribers') then
    raise exception 'Invalid visibility';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;

  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) > 2000 then raise exception 'Post too long'; end if;
  if coalesce(array_length(p_image_paths, 1), 0) > 10 then
    raise exception 'Too many photos';
  end if;
  if p_text = '' and coalesce(array_length(p_image_paths, 1), 0) = 0 then
    raise exception 'Empty post';
  end if;

  select posts_daily_limit into daily_lim from public.app_settings where id = 'global';
  select count(*) into today_count from public.posts
    where author_id = me and created_at >= date_trunc('day', now());
  if today_count >= coalesce(daily_lim, 5) then
    raise exception 'Daily post limit reached';
  end if;

  insert into public.posts (author_id, author_name, author_gender, text, image_path, images, visibility)
    values (me, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_text, coalesce(p_image_paths[1], ''),
            coalesce(p_image_paths, '{}'::text[]), p_visibility)
    returning id into new_id;

  return jsonb_build_object('ok', true, 'id', new_id);
end; $$;
revoke execute on function public.create_post(text, text[], text) from public, anon;
grant execute on function public.create_post(text, text[], text) to authenticated;

-- list_posts — tambahkan field images[]
create or replace function public.list_posts(
  p_scope text default 'all', p_limit int default 30, p_cursor timestamptz default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rows jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_scope not in ('all','following') then p_scope := 'all'; end if;
  p_limit := least(coalesce(p_limit, 30), 50);

  with visible as (
    select p.*
    from public.posts p
    where
      (p_cursor is null or p.created_at < p_cursor)
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
        or p.author_id = me
        or exists (select 1 from public.follows f where f.followee_id = p.author_id and f.follower_id = me)
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
      'images', coalesce(v.images, '{}'),
      'visibility', v.visibility,
      'likeCount', v.like_count,
      'commentCount', v.comment_count,
      'shareCount', v.share_count,
      'isBoosted', v.is_boosted,
      'createdAt', v.created_at,
      'authorAvatar', pr.avatar,
      'isLiked', exists (select 1 from public.post_likes pl where pl.post_id = v.id and pl.user_id = me),
      'isFollowing', exists (select 1 from public.follows f where f.followee_id = v.author_id and f.follower_id = me),
      'isFriend', exists (
        select 1 from public.follows a
        join public.follows b on a.followee_id = b.follower_id and a.follower_id = b.followee_id
        where a.follower_id = me and a.followee_id = v.author_id)
    )
    order by v.is_boosted desc, v.created_at desc
  )
  into rows
  from visible v
  left join public.profiles pr on pr.id = v.author_id;

  return jsonb_build_object('posts', coalesce(rows, '[]'::jsonb));
end; $$;
revoke execute on function public.list_posts(text, int, timestamptz) from public, anon;
grant execute on function public.list_posts(text, int, timestamptz) to authenticated;
