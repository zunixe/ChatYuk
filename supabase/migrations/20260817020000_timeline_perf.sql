-- ============================================================
-- ChatYuk Timeline — Optimasi performa feed
--
-- ⚠️ CARA APPLY: migration ini TIDAK di-apply lewat `supabase db push`
--    (CLI `supabase db query --linked` HANG di Mac ini).
--    DITERAPKAN MANUAL via Supabase Dashboard → SQL Editor
--    (browser automation / Playwright), tanggal 2026-08-17.
--
--    Kalau AI lain / user mau update fungsi list_posts lagi, ikuti
--    cara yang sama: copy isi file ini ke SQL Editor dashboard,
--    atau fix CLI dulu. Jangan asumsikan sudah ter-apply otomatis.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Index pendukung urutan feed: boosted desc → created_at desc
--    (keyset pagination memakai keduanya).
-- ──────────────────────────────────────────────
create index if not exists idx_posts_feed
  on public.posts (is_boosted desc, created_at desc);

-- ──────────────────────────────────────────────
-- 2. RPC list_posts v3 — optimasi + keyset pagination benar
--    Perubahan vs v1 (20260817000000):
--      a. Pagination keyset konsisten dgn ORDER BY:
--         (is_boosted desc, created_at desc) → param p_cursor_boosted.
--         Sebelumnya hanya created_at < cursor → skip/duplikat saat
--         post baru di-boost antar halaman.
--      b. Metadata sosial (isLiked/isFollowing/isFriend) dihitung via
--         LEFT JOIN LATERAL (satu pass per baris, bisa di-optimasi
--         planner) — bukan 3 subquery EXISTS terpisah di SELECT list.
--      c. authorAvatar TETAP di-join dari profiles (client tidak
--         query profiles per post lagi).
-- ──────────────────────────────────────────────
create or replace function public.list_posts(
  p_scope text default 'all',
  p_limit int default 30,
  p_cursor timestamptz default null,
  p_cursor_boosted boolean default false
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
      -- Keyset: halaman berikutnya = ambil baris setelah (is_boosted, created_at)
      -- terakhir yang sudah dilihat, urut boosted desc → created_at desc.
      (p_cursor is null
        or p.is_boosted < p_cursor_boosted
        or (p.is_boosted = p_cursor_boosted and p.created_at < p_cursor))
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
      'isLiked', s.is_liked,
      'isFollowing', s.is_following,
      'isFriend', s.is_friend
    )
    order by v.is_boosted desc, v.created_at desc
  )
  into rows
  from visible v
  left join public.profiles pr on pr.id = v.author_id
  left join lateral (
    select
      exists (select 1 from public.post_likes pl
              where pl.post_id = v.id and pl.user_id = me) as is_liked,
      exists (select 1 from public.follows f
              where f.followee_id = v.author_id and f.follower_id = me) as is_following,
      exists (
        select 1 from public.follows a
        join public.follows b on a.followee_id = b.follower_id and a.follower_id = b.followee_id
        where a.follower_id = me and a.followee_id = v.author_id) as is_friend
  ) s on true;

  return jsonb_build_object('posts', coalesce(rows, '[]'::jsonb));
end; $$;
revoke execute on function public.list_posts(text, int, timestamptz, boolean) from public, anon;
grant execute on function public.list_posts(text, int, timestamptz, boolean) to authenticated;

-- ──────────────────────────────────────────────
-- 3. Realtime: tabel posts WAJIB masuk publication supabase_realtime
--    supaya client (watchNewPosts → onPostgresChanges insert) menerima
--    event post baru. Sebelumnya TIDAK terdaftar → channel diam.
--    (idempotent: sebagian tabel mungkin sudah terdaftar dari apply manual)
-- ──────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['posts', 'post_likes', 'post_comments', 'post_shares'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      null;
    end;
  end loop;
end $$;

-- Hapus signature lama (3 param) supaya tidak ambigu saat RPC dipanggil.
drop function if exists public.list_posts(text, int, timestamptz);