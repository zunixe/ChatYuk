-- Optimasi performa STORY (hanya yang TERBUKTI menguntungkan):
--   1) Index story_views(story_id, viewer_id) — mempercepat cek "sudah
--      dilihat?" per slide saat story_views membesar (planner akan pakai
--      index komposit ini alih-alih scan per story_id).
--   2) RPC baru mark_story_seen_bulk(p_ids uuid[]) — tandai banyak slide
--      dalam SATU round-trip. Dulu viewer mengirim 1 RPC per slide
--      (lihat 10 slide = 10 RPC).
--
-- CATATAN PENTING — kenapa story_tray TIDAK diubah:
-- Sempat direncanakan menulis ulang story_tray dari subquery per-baris
-- (N+1) menjadi LEFT JOIN + DISTINCT ON. Sesudah diukur di DB live,
-- versi JOIN justru LEBIH LAMBAT:
--   data asli (2 author)  : subquery 0.082ms vs join 0.157ms per panggilan
--   simulasi 300 author   : subquery 29.5ms vs join 51.0ms per 100 panggilan
-- Planner PostgreSQL sudah menangani subquery skalar ini dengan baik; JOIN
-- + DISTINCT ON menambah materialisasi yang tidak perlu. Karena itu
-- story_tray DIBIARKAN apa adanya. Jangan "optimalkan" ulang tanpa ukur.

-- ── 1. Index untuk lookup "sudah dilihat?" per slide ──
create index if not exists idx_story_views_story_viewer
  on public.story_views (story_id, viewer_id);

-- ── 2. RPC bulk mark_seen ──
-- SEKALI round-trip untuk semua slide yang benar-benar ditonton.
-- Guard sama dengan mark_story_seen: hanya slide yang boleh dilihat user
-- (visibility/block) yang ditandai — id asing diabaikan diam-diam.
create or replace function public.mark_story_seen_bulk(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  uid uuid := auth.uid();
  n integer := 0;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_ids is null or array_length(p_ids, 1) is null then return 0; end if;

  insert into public.story_views (story_id, viewer_id)
  select s.id, uid
  from public.stories s
  where s.id = any (p_ids)
    and s.expires_at > now()
    and (
      s.author_id = uid
      or (
        (s.visibility = 'everyone')
        or (s.visibility = 'followers' and exists (
              select 1 from public.follows f
              where f.follower_id = uid and f.followee_id = s.author_id))
        or (s.visibility = 'friends'
            and public._are_friends(uid, s.author_id))
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = uid and b.blocked_id = s.author_id)
           or (b.blocker_id = s.author_id and b.blocked_id = uid)
      )
    )
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$fn$;

revoke execute on function public.mark_story_seen_bulk(uuid[]) from public, anon;
grant execute on function public.mark_story_seen_bulk(uuid[]) to authenticated;
