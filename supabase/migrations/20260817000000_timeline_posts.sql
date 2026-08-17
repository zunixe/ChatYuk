-- ============================================================
-- ChatYuk Timeline — Postingan publik + interaksi sosial
--
-- Prinsip ekonomi koin:
--   - POSTING = GRATIS (rate-limit harian anti-flood: posts_daily_limit).
--   - Like / Comment / Share = GRATIS, TIDAK menghasilkan koin.
--   - Follow / Unfollow / Friend = GRATIS, TIDAK menghasilkan koin.
--   - Boost post = BERBAYAR (dual pricing paid/bonus) → naik ke atas feed.
--   - Subscribe creator = BERBAYAR (sudah ada) → akses post 'subscribers'.
--
-- Visibilitas post: public (semua) > followers (author + follower + teman +
-- subscriber) > subscribers (author + subscriber aktif saja).
-- Subscriber otomatis melihat semua level di bawahnya.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Konfigurasi app_settings
-- ──────────────────────────────────────────────
alter table public.app_settings
  add column if not exists cost_post_boost   int not null default 50,
  add column if not exists post_boost_hours  int not null default 24,
  add column if not exists posts_daily_limit int not null default 5,
  add column if not exists bonus_first_friend int not null default 20;

-- ──────────────────────────────────────────────
-- 2. Tabel posts
-- ──────────────────────────────────────────────
create table if not exists public.posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references public.profiles(id) on delete cascade,
  author_name   text not null default 'Anon',
  author_gender text not null default 'other',
  text          text not null default '',
  image_path    text not null default '',
  visibility    text not null default 'public'
                check (visibility in ('public','followers','subscribers')),
  like_count    int not null default 0,
  comment_count int not null default 0,
  share_count   int not null default 0,
  is_boosted    boolean not null default false,
  boosted_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists idx_posts_created on public.posts(created_at desc);
create index if not exists idx_posts_author on public.posts(author_id, created_at desc);

alter table public.posts enable row level security;

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select using (
  -- public → semua; followers → author/follower/teman/subscriber aktif;
  -- subscribers → author/subscriber aktif.
  (visibility = 'public')
  or (visibility = 'followers' and (
        author_id = auth.uid()
        or exists (select 1 from public.follows f where f.followee_id = posts.author_id and f.follower_id = auth.uid())
        or exists (select 1 from public.subscriptions s where s.creator_id = posts.author_id and s.subscriber_id = auth.uid() and s.expires_at > now())
     ))
  or (visibility = 'subscribers' and (
        author_id = auth.uid()
        or exists (select 1 from public.subscriptions s where s.creator_id = posts.author_id and s.subscriber_id = auth.uid() and s.expires_at > now())
     ))
  -- filter blokir dua arah (konsisten private_messages)
  and not exists (select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = posts.author_id)
           or (b.blocker_id = posts.author_id and b.blocked_id = auth.uid()))
);

drop policy if exists posts_insert_own on public.posts;
create policy posts_insert_own on public.posts for insert with check (auth.uid() = author_id);

drop policy if exists posts_update_own on public.posts;
create policy posts_update_own on public.posts for update using (auth.uid() = author_id);

drop policy if exists posts_delete_own on public.posts;
create policy posts_delete_own on public.posts for delete using (auth.uid() = author_id);

-- ──────────────────────────────────────────────
-- 3. Tabel post_likes / post_comments / post_shares
-- ──────────────────────────────────────────────
create table if not exists public.post_likes (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_likes enable row level security;
drop policy if exists post_likes_select on public.post_likes;
create policy post_likes_select on public.post_likes for select using (true);
drop policy if exists post_likes_insert_own on public.post_likes;
create policy post_likes_insert_own on public.post_likes for insert with check (auth.uid() = user_id);
drop policy if exists post_likes_delete_own on public.post_likes;
create policy post_likes_delete_own on public.post_likes for delete using (auth.uid() = user_id);

create table if not exists public.post_comments (
  id          bigint generated always as identity primary key,
  post_id     uuid not null references public.posts(id) on delete cascade,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  author_name text not null default 'Anon',
  text        text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists idx_post_comments_post on public.post_comments(post_id, created_at);
alter table public.post_comments enable row level security;
drop policy if exists post_comments_select on public.post_comments;
create policy post_comments_select on public.post_comments for select using (true);
drop policy if exists post_comments_insert_own on public.post_comments;
create policy post_comments_insert_own on public.post_comments for insert with check (auth.uid() = author_id);
drop policy if exists post_comments_delete_own on public.post_comments;
create policy post_comments_delete_own on public.post_comments for delete using (auth.uid() = author_id);

create table if not exists public.post_shares (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_shares enable row level security;
drop policy if exists post_shares_select on public.post_shares;
create policy post_shares_select on public.post_shares for select using (true);
drop policy if exists post_shares_insert_own on public.post_shares;
create policy post_shares_insert_own on public.post_shares for insert with check (auth.uid() = user_id);

-- ──────────────────────────────────────────────
-- 4. Trigger sinkron counter like/comment
-- ──────────────────────────────────────────────
create or replace function public.post_like_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set like_count = like_count + 1 where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
    return old;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists post_like_count_trigger on public.post_likes;
create trigger post_like_count_trigger after insert or delete on public.post_likes
  for each row execute function public.post_like_count_sync();

create or replace function public.post_comment_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comment_count = comment_count + 1 where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
    return old;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists post_comment_count_trigger on public.post_comments;
create trigger post_comment_count_trigger after insert or delete on public.post_comments
  for each row execute function public.post_comment_count_sync();

-- ──────────────────────────────────────────────
-- 5. RPC create_post — GRATIS (rate-limit harian, registered only)
-- ──────────────────────────────────────────────
create or replace function public.create_post(
  p_text text default '', p_image_path text default '', p_visibility text default 'public'
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
  if p_text = '' and coalesce(p_image_path, '') = '' then
    raise exception 'Empty post';
  end if;

  select posts_daily_limit into daily_lim from public.app_settings where id = 'global';
  select count(*) into today_count from public.posts
    where author_id = me and created_at >= date_trunc('day', now());
  if today_count >= coalesce(daily_lim, 5) then
    raise exception 'Daily post limit reached';
  end if;

  insert into public.posts (author_id, author_name, author_gender, text, image_path, visibility)
    values (me, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_text, coalesce(p_image_path,''), p_visibility)
    returning id into new_id;

  return jsonb_build_object('ok', true, 'id', new_id);
end; $$;
revoke execute on function public.create_post(text, text, text) from public, anon;
grant execute on function public.create_post(text, text, text) to authenticated;

-- ──────────────────────────────────────────────
-- 6. RPC toggle_post_like — GRATIS
-- ──────────────────────────────────────────────
create or replace function public.toggle_post_like(p_post_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); liked boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'Post not found';
  end if;
  if exists (select 1 from public.post_likes where post_id = p_post_id and user_id = me) then
    delete from public.post_likes where post_id = p_post_id and user_id = me;
    liked := false;
  else
    insert into public.post_likes (post_id, user_id) values (p_post_id, me);
    liked := true;
  end if;
  return jsonb_build_object('ok', true, 'liked', liked);
end; $$;
revoke execute on function public.toggle_post_like(uuid) from public, anon;
grant execute on function public.toggle_post_like(uuid) to authenticated;

-- ──────────────────────────────────────────────
-- 7. RPC add_post_comment — GRATIS
-- ──────────────────────────────────────────────
create or replace function public.add_post_comment(p_post_id uuid, p_text text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); my_name text; new_id bigint;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) = 0 or length(p_text) > 500 then
    raise exception 'Invalid comment';
  end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'Post not found';
  end if;
  select nickname into my_name from public.profiles where id = me;
  insert into public.post_comments (post_id, author_id, author_name, text)
    values (p_post_id, me, coalesce(my_name,'Anon'), p_text)
    returning id into new_id;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $$;
revoke execute on function public.add_post_comment(uuid, text) from public, anon;
grant execute on function public.add_post_comment(uuid, text) to authenticated;

-- ──────────────────────────────────────────────
-- 8. RPC share_post — GRATIS, dedupe per user
-- ──────────────────────────────────────────────
create or replace function public.share_post(p_post_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'Post not found';
  end if;
  insert into public.post_shares (post_id, user_id) values (p_post_id, me)
    on conflict do nothing;
  if found then
    update public.posts set share_count = share_count + 1 where id = p_post_id;
  end if;
  select share_count into c from public.posts where id = p_post_id;
  return jsonb_build_object('ok', true, 'share_count', c);
end; $$;
revoke execute on function public.share_post(uuid) from public, anon;
grant execute on function public.share_post(uuid) to authenticated;

-- ──────────────────────────────────────────────
-- 9. RPC boost_post — BERBAYAR (dual pricing), author only
-- ──────────────────────────────────────────────
create or replace function public.boost_post(p_post_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); p record; points_on boolean;
  paid int; bonus_p int; mult int; hours int; res jsonb; remaining int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into p from public.posts where id = p_post_id;
  if not found then raise exception 'Post not found'; end if;
  if p.author_id <> me then raise exception 'Not author'; end if;
  if p.is_boosted then raise exception 'Already boosted'; end if;

  select points_enabled, cost_post_boost, bonus_price_multiplier, post_boost_hours
    into points_on, paid, mult, hours from public.app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(me, 'post_boost', paid, bonus_p, p_post_id::text);
    remaining := (res->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = me;
  end if;

  update public.posts
    set is_boosted = true, boosted_at = now()
    where id = p_post_id;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0));
end; $$;
revoke execute on function public.boost_post(uuid) from public, anon;
grant execute on function public.boost_post(uuid) to authenticated;

-- ──────────────────────────────────────────────
-- 10. RPC list_posts — feed + metadata sosial
--     scope: 'all' | 'following'. Urutan: boosted desc → created_at desc.
-- ──────────────────────────────────────────────
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
      -- cursor pagination by created_at (boosted order tetap konsisten di
      -- halaman yang sama; skip yang sudah lewat cursor)
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

-- ──────────────────────────────────────────────
-- 11. RPC timeline_pricing — biaya boost untuk UI
-- ──────────────────────────────────────────────
create or replace function public.timeline_pricing()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return (select jsonb_build_object(
    'boost_paid', cost_post_boost,
    'boost_bonus', cost_post_boost * bonus_price_multiplier,
    'multiplier', bonus_price_multiplier,
    'posts_daily_limit', posts_daily_limit
  ) from public.app_settings where id = 'global');
end; $$;
revoke execute on function public.timeline_pricing() from public, anon;
grant execute on function public.timeline_pricing() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 12. Bonus first-friend — one_time_bonus (sekali)
--     valid_actions + mapping bonus_first_friend.
-- ──────────────────────────────────────────────
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int language plpgsql security definer set search_path = public as $$
declare
  valid_actions text[]; nominal int; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  valid_actions := array['registered','rated_app','completed_profile',
    'shared_app','invited_friend','first_photo','first_room_chat',
    'online_5min','online_30min','online_60min','online_120min',
    'first_friend'];
  if not (action_key = any(valid_actions)) then
    raise exception 'Invalid action key: %', action_key;
  end if;

  -- Nominal dibaca dari server, bukan dari client (anti-farming).
  select
    case action_key
      when 'registered'        then bonus_registered
      when 'rated_app'         then bonus_rated
      when 'completed_profile' then bonus_profile
      when 'shared_app'        then bonus_shared
      when 'invited_friend'    then bonus_invited
      when 'first_photo'       then bonus_first_photo
      when 'first_room_chat'   then bonus_first_room
      when 'online_5min'       then bonus_online_5min
      when 'online_30min'      then bonus_online_30min
      when 'online_60min'      then bonus_online_60min
      when 'online_120min'     then bonus_online_120min
      when 'first_friend'      then bonus_first_friend
      else 0
    end
  into nominal from app_settings where id = 'global';

  if exists (select 1 from profiles where id = auth.uid()
             and one_time_actions->>action_key = 'true') then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
    where id = auth.uid();

  tot := public.ledger_credit(auth.uid(), 'bonus', 'one_time', nominal,
           null, jsonb_build_object('action', action_key));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'bonus', nominal, jsonb_build_object('action', action_key));

  return tot;
end; $$;
grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;

-- Beri bonus first-friend saat pertemanan pertama diterima.
create or replace function public.respond_friend_request(p_request_id bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); req record; friend_count int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into req from friend_requests where id = p_request_id and to_id = me;
  if not found then raise exception 'Request not found'; end if;
  if req.status <> 'pending' then raise exception 'Already responded'; end if;

  update friend_requests set status = case when p_accept then 'accepted' else 'rejected' end,
    responded_at = now() where id = p_request_id;

  if p_accept then
    insert into follows (follower_id, followee_id) values (req.from_id, req.to_id)
      on conflict do nothing;
    insert into follows (follower_id, followee_id) values (req.to_id, req.from_id)
      on conflict do nothing;

    -- Bonus first-friend untuk KEDUA belah pihak (sekali seumur hidup).
    select friends_count into friend_count from public.profiles where id = req.from_id;
    if coalesce(friend_count, 0) <= 1 then
      perform public.one_time_bonus('first_friend', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'accepted', p_accept);
end; $$;
revoke execute on function public.respond_friend_request(bigint, boolean) from public, anon;
grant execute on function public.respond_friend_request(bigint, boolean) to authenticated;

-- ──────────────────────────────────────────────
-- 13. Storage: bucket chat-photos sudah public read + insert authenticated
--     (dari migration 20260813000000_chat_photos_storage.sql). Post image
--     memakai path 'posts/<uid>/<ts>.jpg' di bucket yang sama.
-- ──────────────────────────────────────────────
