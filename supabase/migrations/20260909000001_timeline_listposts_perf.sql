-- ============================================================
-- list_posts v6 — optimasi performa feed
--
-- ⚠️ CARA APPLY: migration ini TIDAK di-apply lewat `supabase db push`
--    (CLI hang di Mac ini). Terapkan MANUAL via Supabase Dashboard →
--    SQL Editor, sama seperti pola 20260817020000_timeline_perf.sql.
--
-- Masalah: versi sebelumnya mengevaluasi per-baris EXISTS
--   (follows/subscriptions/blocks) atas SEMUA row posts sebelum
--   ORDER BY+LIMIT, plus self-join follows per post untuk is_friend.
--   Semakin banyak post, setiap pemanggilan RPC makin lambat —
--   tab Timeline terasa "loading lama" setiap masuk.
--
-- Perbaikan (behavior IDENTIK, hanya rencana eksekusi):
--   1. Followee/subscriber/blocked diambil SEKALI ke array — filter
--      pakai = any(...) / <> all(...) yang bisa diselesaikan planner
--      tanpa subquery per baris.
--   2. is_following dari array followers (tanpa EXISTS per baris).
--   3. is_liked & is_friend tetap EXISTS (sudah didukung index
--      PK post_likes + idx_follows_follower/followee, hanya 30 baris).
--   4. Index feed global dipastikan ada (idempotent).
-- ============================================================

create index if not exists idx_posts_feed
  on public.posts (is_boosted desc, created_at desc);

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
