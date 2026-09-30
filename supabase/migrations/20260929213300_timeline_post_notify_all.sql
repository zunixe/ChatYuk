-- ============================================================
-- Notif post timeline sesuai visibilitas + RPC get_post.
--
-- MINTA USER:
--   - post PUBLIC → notifikasi untuk SEMUA user (dulu hanya follower),
--     tap notif → masuk ke postingannya;
--   - post FOLLOWERS → hanya follower;
--   - post SUBSCRIBERS → hanya subscriber aktif.
--
-- ISI:
--   1) notify_post_followers: cabang 'public' → loop SEMUA profil
--      registered non-dummy non-exclude (kecuali author; skip bila ada
--      blokir dua arah). Cabang followers/subscribers tetap.
--   2) notify_timeline_post_fanout: HANYA untuk 'public' (sebelumnya
--      fanout topic untuk SEMUA visibilitas → bocor isi followers/
--      subscribers-only ke topic publik).
--   3) get_post(p_id) BARU → 1 post (bentuk sama seperti item
--      list_posts) bila viewer boleh lihat, else NULL. Dipakai layar
--      detail post dari tap notifikasi.
--
-- SUMBER: notify_post_followers + notify_timeline_post_fanout = live
--   (trigger posts_notify_followers_trigger / posts_timeline_fanout_trigger,
--   definisi lain utuh); get_post = bentuk item list_posts @5-param.
--
-- CARA APPLY: Management API (CLI db push HANG).
-- ROLLBACK: re-apply definisi lama kedua trigger-fn + drop get_post.
-- ============================================================

-- ── 1) notify_post_followers: public → semua ──
create or replace function public.notify_post_followers()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
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
  elsif new.visibility = 'followers' then
    -- followers -> hanya follower
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
    -- public (dan fallback) -> SEMUA user: registered, bukan dummy,
    -- bukan exclude, bukan author, tanpa blokir dua arah.
    for rec in
      select p.id as uid
      from public.profiles p
      where p.id <> new.author_id
        and coalesce(p.is_registered, false) = true
        and p.id not in (select du from public.admin_dummy_uids() du)
        and not (p.id = any(coalesce(
          (select array_agg(ae) from public.admin_excluded_uids() ae),
          '{}'::uuid[])))
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = p.id and b.blocked_id = new.author_id)
             or (b.blocker_id = new.author_id and b.blocked_id = p.id)
        )
      limit 2000
    loop
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

  return new;
exception when others then
  -- jangan gagalkan insert post jika push gagal
  return new;
end;
$fn$;

-- ── 2) fanout topic HANYA untuk public ──
create or replace function public.notify_timeline_post_fanout()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if coalesce(new.visibility, 'public') <> 'public' then
    return new;
  end if;
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','timeline','id', new.id::text)
  );
  return new;
end;
$fn$;

-- ── 3) get_post: 1 post untuk layar detail (tap notif) ──
create or replace function public.get_post(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  v_followers uuid[] := '{}';
  v_subs uuid[] := '{}';
  v_blocked uuid[] := '{}';
  result jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_id is null then return null; end if;

  select coalesce(array_agg(f.followee_id), '{}') into v_followers
  from public.follows f where f.follower_id = me;

  select coalesce(array_agg(s.creator_id), '{}') into v_subs
  from public.subscriptions s
  where s.subscriber_id = me and s.expires_at > now();

  select coalesce(array_agg(
    case when b.blocker_id = me then b.blocked_id else b.blocker_id end
  ), '{}') into v_blocked
  from public.blocks b
  where b.blocker_id = me or b.blocked_id = me;

  select jsonb_build_object(
    'id', v.id,
    'authorId', v.author_id,
    'authorName', v.author_name,
    'authorGender', v.author_gender,
    'text', v.text,
    'imagePath', v.image_path,
    'images', coalesce(v.images, '{}'),
    'imageW', coalesce(v.image_w, 0),
    'imageH', coalesce(v.image_h, 0),
    'imageDims', coalesce(v.image_dims, '[]'::jsonb),
    'visibility', v.visibility,
    'likeCount', v.like_count,
    'commentCount', v.comment_count,
    'shareCount', v.share_count,
    'isBoosted', v.is_boosted,
    'createdAt', v.created_at,
    'authorAvatar', pr.avatar,
    'isLiked', exists(
      select 1 from public.post_likes pl
      where pl.post_id = v.id and pl.user_id = me),
    'isFollowing', (v.author_id = any(v_followers)),
    'isFriend', exists (
      select 1 from public.follows a
      join public.follows b on a.followee_id = b.follower_id
        and a.follower_id = b.followee_id
      where a.follower_id = me and a.followee_id = v.author_id),
    'country', v.country
  ) into result
  from public.posts v
  left join public.profiles pr on pr.id = v.author_id
  where v.id = p_id
    and (
      v.visibility = 'public'
      or v.author_id = me
      or (v.visibility = 'followers' and v.author_id = any(v_followers))
      or (v.visibility = 'followers' and v.author_id = any(v_subs))
      or (v.visibility = 'subscribers' and v.author_id = any(v_subs))
    )
    and v.author_id <> all(v_blocked);

  return result;
end;
$fn$;

revoke execute on function public.get_post(uuid) from public, anon;
grant execute on function public.get_post(uuid) to authenticated;
