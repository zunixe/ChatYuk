-- ============================================================
-- Notifikasi timeline: jika orang yang kamu ikuti membuat post baru,
-- kirim push ke semua follower (dan subscriber untuk post khusus)
-- ============================================================

create or replace function public.notify_post_followers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  author_name text;
  rec record;
  notif_title text;
  notif_body text;
begin
  -- ambil nama author
  select nickname into author_name from public.profiles where id = new.author_id;
  author_name := coalesce(author_name, 'User');

  -- preview text untuk body notifikasi (potong 80 char)
  notif_body := left(coalesce(new.text, ''), 80);
  if notif_body = '' then
    if new.image_path <> '' then
      notif_body := '[Foto]';
    else
      notif_body := 'membuat postingan baru';
    end if;
  end if;

  notif_title := author_name;

  -- Untuk post visibility subscribers -> hanya subscriber aktif
  if new.visibility = 'subscribers' then
    for rec in
      select s.subscriber_id as uid
      from public.subscriptions s
      where s.creator_id = new.author_id
        and s.expires_at > now()
        and s.subscriber_id <> new.author_id
      limit 1000
    loop
      -- skip jika ada block
      if exists (
        select 1 from public.blocks b
        where (b.blocker_id = rec.uid and b.blocked_id = new.author_id)
           or (b.blocker_id = new.author_id and b.blocked_id = rec.uid)
      ) then
        continue;
      end if;

      perform public.social_push(
        rec.uid,
        notif_title,
        notif_body,
        jsonb_build_object(
          'type', 'timeline_post',
          'postId', new.id,
          'authorId', new.author_id,
          'authorName', author_name
        )
      );
    end loop;
  else
    -- public / followers -> notifikasi ke followers
    for rec in
      select f.follower_id as uid
      from public.follows f
      where f.followee_id = new.author_id
        and f.follower_id <> new.author_id
      limit 1000
    loop
      if exists (
        select 1 from public.blocks b
        where (b.blocker_id = rec.uid and b.blocked_id = new.author_id)
           or (b.blocker_id = new.author_id and b.blocked_id = rec.uid)
      ) then
        continue;
      end if;

      -- untuk followers visibility, pastikan follower tidak ke-skip
      -- (public sudah pasti visible, followers juga)
      perform public.social_push(
        rec.uid,
        notif_title,
        notif_body,
        jsonb_build_object(
          'type', 'timeline_post',
          'postId', new.id,
          'authorId', new.author_id,
          'authorName', author_name
        )
      );
    end loop;

    -- untuk public, juga notifikasi ke subscriber yang mungkin belum follow
    if new.visibility = 'public' then
      for rec in
        select s.subscriber_id as uid
        from public.subscriptions s
        where s.creator_id = new.author_id
          and s.expires_at > now()
          and s.subscriber_id <> new.author_id
          and not exists (
            select 1 from public.follows f
            where f.followee_id = new.author_id and f.follower_id = s.subscriber_id
          )
        limit 1000
      loop
        if exists (
          select 1 from public.blocks b
          where (b.blocker_id = rec.uid and b.blocked_id = new.author_id)
             or (b.blocker_id = new.author_id and b.blocked_id = rec.uid)
        ) then
          continue;
        end if;
        perform public.social_push(
          rec.uid,
          notif_title,
          notif_body,
          jsonb_build_object(
            'type', 'timeline_post',
            'postId', new.id,
            'authorId', new.author_id,
            'authorName', author_name
          )
        );
      end loop;
    end if;
  end if;

  return new;
exception when others then
  -- jangan gagalkan insert post jika push gagal
  return new;
end;
$$;

drop trigger if exists posts_notify_followers_trigger on public.posts;
create trigger posts_notify_followers_trigger
  after insert on public.posts
  for each row execute function public.notify_post_followers();
