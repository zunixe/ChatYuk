-- ============================================================
-- ChatYuk Timeline — Interaksi komentar: like / reply / share + waktu
--
-- Postingan & komentar GRATIS. Like/Reply/Share komentar juga GRATIS.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Kolom baru di post_comments
-- ──────────────────────────────────────────────
alter table public.post_comments
  add column if not exists like_count  int not null default 0,
  add column if not exists share_count int not null default 0,
  add column if not exists parent_id   bigint references public.post_comments(id) on delete cascade;

create index if not exists idx_post_comments_parent on public.post_comments(post_id, parent_id, created_at);

-- ──────────────────────────────────────────────
-- 2. Tabel comment_likes / comment_shares
-- ──────────────────────────────────────────────
create table if not exists public.comment_likes (
  comment_id bigint not null references public.post_comments(id) on delete cascade,
  user_id    uuid   not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
alter table public.comment_likes enable row level security;
drop policy if exists comment_likes_select on public.comment_likes;
create policy comment_likes_select on public.comment_likes for select using (true);
drop policy if exists comment_likes_insert_own on public.comment_likes;
create policy comment_likes_insert_own on public.comment_likes for insert with check (auth.uid() = user_id);
drop policy if exists comment_likes_delete_own on public.comment_likes;
create policy comment_likes_delete_own on public.comment_likes for delete using (auth.uid() = user_id);

create table if not exists public.comment_shares (
  comment_id bigint not null references public.post_comments(id) on delete cascade,
  user_id    uuid   not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
alter table public.comment_shares enable row level security;
drop policy if exists comment_shares_select on public.comment_shares;
create policy comment_shares_select on public.comment_shares for select using (true);
drop policy if exists comment_shares_insert_own on public.comment_shares;
create policy comment_shares_insert_own on public.comment_shares for insert with check (auth.uid() = user_id);
drop policy if exists comment_shares_delete_own on public.comment_shares;
create policy comment_shares_delete_own on public.comment_shares for delete using (auth.uid() = user_id);

-- ──────────────────────────────────────────────
-- 3. Trigger sinkron counter like/share komentar
-- ──────────────────────────────────────────────
create or replace function public.comment_like_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.post_comments set like_count = like_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.post_comments set like_count = greatest(like_count - 1, 0) where id = old.comment_id;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists comment_like_count_trigger on public.comment_likes;
create trigger comment_like_count_trigger after insert or delete on public.comment_likes
  for each row execute function public.comment_like_count_sync();

create or replace function public.comment_share_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.post_comments set share_count = share_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.post_comments set share_count = greatest(share_count - 1, 0) where id = old.comment_id;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists comment_share_count_trigger on public.comment_shares;
create trigger comment_share_count_trigger after insert or delete on public.comment_shares
  for each row execute function public.comment_share_count_sync();

-- ──────────────────────────────────────────────
-- 4. RPC list_post_comments — daftar komentar + status like user
-- ──────────────────────────────────────────────
create or replace function public.list_post_comments(p_post_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); rows jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'postId', c.post_id,
      'authorId', c.author_id,
      'authorName', c.author_name,
      'text', c.text,
      'likeCount', c.like_count,
      'shareCount', c.share_count,
      'parentId', c.parent_id,
      'createdAt', c.created_at,
      'isLiked', exists (select 1 from public.comment_likes cl
                          where cl.comment_id = c.id and cl.user_id = me)
    ) order by c.created_at
  ), '[]'::jsonb) into rows
  from public.post_comments c
  where c.post_id = p_post_id;
  return rows;
end; $$;
revoke execute on function public.list_post_comments(uuid) from public, anon;
grant execute on function public.list_post_comments(uuid) to authenticated;

-- ──────────────────────────────────────────────
-- 5. RPC toggle_comment_like — GRATIS
-- ──────────────────────────────────────────────
create or replace function public.toggle_comment_like(p_comment_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); liked boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.post_comments where id = p_comment_id) then
    raise exception 'Comment not found';
  end if;
  if exists (select 1 from public.comment_likes where comment_id = p_comment_id and user_id = me) then
    delete from public.comment_likes where comment_id = p_comment_id and user_id = me;
    liked := false;
  else
    insert into public.comment_likes (comment_id, user_id) values (p_comment_id, me);
    liked := true;
  end if;
  return jsonb_build_object('ok', true, 'liked', liked);
end; $$;
revoke execute on function public.toggle_comment_like(bigint) from public, anon;
grant execute on function public.toggle_comment_like(bigint) to authenticated;

-- ──────────────────────────────────────────────
-- 6. RPC reply_post_comment — balasan komentar (parent harus di post sama)
-- ──────────────────────────────────────────────
create or replace function public.reply_post_comment(p_post_id uuid, p_parent_id bigint, p_text text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); my_name text; new_id bigint;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) = 0 or length(p_text) > 500 then
    raise exception 'Invalid comment';
  end if;
  if not exists (select 1 from public.post_comments
                  where id = p_parent_id and post_id = p_post_id) then
    raise exception 'Parent not found';
  end if;
  select nickname into my_name from public.profiles where id = me;
  insert into public.post_comments (post_id, author_id, author_name, text, parent_id)
    values (p_post_id, me, coalesce(my_name,'Anon'), p_text, p_parent_id)
    returning id into new_id;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $$;
revoke execute on function public.reply_post_comment(uuid, bigint, text) from public, anon;
grant execute on function public.reply_post_comment(uuid, bigint, text) to authenticated;

-- ──────────────────────────────────────────────
-- 7. RPC share_post_comment — GRATIS, dedupe per user
-- ──────────────────────────────────────────────
create or replace function public.share_post_comment(p_comment_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.post_comments where id = p_comment_id) then
    raise exception 'Comment not found';
  end if;
  insert into public.comment_shares (comment_id, user_id) values (p_comment_id, me)
    on conflict do nothing;
  if found then
    update public.post_comments set share_count = share_count + 1 where id = p_comment_id;
  end if;
  select share_count into c from public.post_comments where id = p_comment_id;
  return jsonb_build_object('ok', true, 'share_count', c);
end; $$;
revoke execute on function public.share_post_comment(bigint) from public, anon;
grant execute on function public.share_post_comment(bigint) to authenticated;
