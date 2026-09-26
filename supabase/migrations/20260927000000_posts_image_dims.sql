-- ============================================================
-- ChatYuk Timeline — Dimensi foto post (rasio asli)
--
-- menyentuh: list_posts (FROZEN)
-- menyentuh: create_post
--
-- Tujuan: feed bisa menampilkan foto dengan RASIO ASLI (ala Threads)
-- tanpa layout shift — lebar penuh, tinggi = lebar/rasio (di-clamp di
-- client). Dimensi disimpan saat create_post, dikembalikan list_posts.
--
-- Kolom:
--   image_w    int   = lebar foto PERTAMA (0 = tidak diketahui/post lama)
--   image_h    int   = tinggi foto PERTAMA
--   image_dims jsonb = array [{w,h}, ...] sejajar dengan `images[]`
--
-- ⚠️ CARA APPLY: via Supabase Management API (CLI `db push` HANG di Mac
--    ini — lihat supabase/migrations/APPLIED_VIA_API.md):
--      POST https://api.supabase.com/v1/projects/fohcucyyejdryryoxitm/database/query
--    lalu catat versi ke supabase_migrations.schema_migrations.
--
-- ⚠️ list_posts & create_post pakai 4-arg / 3-arg BARU. Overload lama
--    di-drop supaya tidak ambigu (PostgREST/RPC JSON mengirim param
--    named; dua overload = "function is not unique").
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Kolom dimensi foto
-- ──────────────────────────────────────────────
alter table public.posts
  add column if not exists image_w    int   not null default 0,
  add column if not exists image_h    int   not null default 0,
  add column if not exists image_dims jsonb not null default '[]'::jsonb;

-- ──────────────────────────────────────────────
-- 2. create_post — terima p_image_dims
--    [{w,h}, ...] sejajar dengan p_image_paths.
-- ──────────────────────────────────────────────
-- Drop overload 3-arg lama (path/visibility) supaya hanya ada SATU
-- create_post di schema (hindari ambiguity saat RPC).
drop function if exists public.create_post(text, text[], text);

create or replace function public.create_post(
  p_text text default '',
  p_image_paths text[] default '{}',
  p_visibility text default 'public',
  p_image_dims jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  am_registered boolean; my_name text; my_gender text;
  daily_lim int; today_count int; new_id uuid;
  v_w int := 0; v_h int := 0; v_dims jsonb;
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
  if coalesce(array_length(p_image_paths, 1), 0) > 5 then
    raise exception 'Too many photos';
  end if;
  if p_text = '' and coalesce(array_length(p_image_paths, 1), 0) = 0 then
    raise exception 'Empty post';
  end if;

  -- Normalisasi dimensi: pakai elemen pertama yang valid untuk image_w/h.
  v_dims := case when jsonb_typeof(p_image_dims) = 'array'
                 then p_image_dims else '[]'::jsonb end;
  if jsonb_array_length(v_dims) > 0 then
    v_w := coalesce((v_dims->0->>'w')::int, 0);
    v_h := coalesce((v_dims->0->>'h')::int, 0);
    if v_w < 0 then v_w := 0; end if;
    if v_h < 0 then v_h := 0; end if;
  end if;

  select posts_daily_limit into daily_lim from public.app_settings where id = 'global';
  select count(*) into today_count from public.posts
    where author_id = me and created_at >= date_trunc('day', now());
  if today_count >= coalesce(daily_lim, 5) then
    raise exception 'Daily post limit reached';
  end if;

  insert into public.posts (
    author_id, author_name, author_gender, text, image_path, images,
    image_w, image_h, image_dims, visibility)
    values (me, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_text, coalesce(p_image_paths[1], ''),
            coalesce(p_image_paths, '{}'::text[]),
            v_w, v_h, v_dims, p_visibility)
    returning id into new_id;

  return jsonb_build_object(
    'ok', true,
    'id', new_id,
    'daily_remaining', greatest(0, coalesce(daily_lim, 5) - today_count - 1)
  );
end; $$;

revoke execute on function public.create_post(text, text[], text, jsonb) from public, anon;
grant execute on function public.create_post(text, text[], text, jsonb) to authenticated;

-- ──────────────────────────────────────────────
-- 3. list_posts — kembalikan imageW/imageH/imageDims
--    (dasar = definisi live v6 @ 20260909000001_timeline_listposts_perf.sql;
--     HANYA menambah field output, cabang lain IDENTIK).
-- ──────────────────────────────────────────────
-- Drop overload 5-arg lama (scope/limit/cursor/boosted/country) supaya
-- hanya ada SATU list_posts (signature akhir tetap 5-arg — hanya output
-- yang berubah).
drop function if exists public.list_posts(text, int, timestamptz, boolean, text);

create or replace function public.list_posts(
  p_scope text default 'all',
  p_limit int default 30,
  p_cursor timestamptz default null,
  p_cursor_boosted boolean default false,
  p_country text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  rows jsonb;
  v_followers uuid[] := '{}';
  v_subs uuid[] := '{}';
  v_blocked uuid[] := '{}';
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Timeline registered-only (ABSOLUT, tak tergantung toggle):
  -- anon tidak pernah bisa lihat timeline/post (bypass: dummy & admin).
  if exists (
    select 1 from public.profiles p
    where p.id = me and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'ANON_DISABLED';
  end if;
  if p_scope not in ('all','following','mine') then p_scope := 'all'; end if;
  p_limit := least(coalesce(p_limit, 30), 50);

  -- Ambil set relasi SEKALI (index-supported, 1 query masing-masing)
  -- daripada EXISTS per baris posts.
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

  with visible as (
    select p.*
    from public.posts p
    where
      (p_cursor is null
        or p.is_boosted < p_cursor_boosted
        or (p.is_boosted = p_cursor_boosted and p.created_at < p_cursor))
      and (
        p.visibility = 'public'
        or p.author_id = me
        or (p.visibility = 'followers' and p.author_id = any(v_followers))
        or (p.visibility = 'followers' and p.author_id = any(v_subs))
        or (p.visibility = 'subscribers' and p.author_id = any(v_subs))
      )
      and p.author_id <> all(v_blocked)
      and (
        p_scope = 'all'
        or (p_scope = 'mine' and p.author_id = me)
        or (p_scope = 'following' and p.author_id = any(v_followers))
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
      (v.author_id = any(v_followers)) as is_following,
      exists (
        select 1 from public.follows a
        join public.follows b on a.followee_id = b.follower_id and a.follower_id = b.followee_id
        where a.follower_id = me and a.followee_id = v.author_id) as is_friend
  ) s on true;

  return jsonb_build_object('posts', coalesce(rows, '[]'::jsonb));
end;
$fn$;

revoke execute on function public.list_posts(text, int, timestamptz, boolean, text) from public, anon;
grant execute on function public.list_posts(text, int, timestamptz, boolean, text) to authenticated;
