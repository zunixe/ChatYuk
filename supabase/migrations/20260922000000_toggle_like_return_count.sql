-- ============================================================
-- Fix: toggle_post_like / toggle_comment_like mengembalikan like_count
--
-- Masalah: UI menampilkan jumlah like = 2 padahal harusnya 1.
--
-- Root cause: RPC toggle hanya mengembalikan {ok, liked} TANPA
-- like_count. Frontend lalu menghitung sendiri `cur + 1` / `cur - 1`
-- dari nilai LOKAL. Sementara itu, trigger `post_like_count_sync`
-- (AFTER INSERT/DELETE) meng-update posts.like_count, yang memicu
-- event REALTIME UPDATE pada tabel posts. Event realtime itu
-- menimpa likeCount lokal dengan nilai server.
--
-- Balapan (race):
--   1) Tap like → RPC jalan.
--   2) Realtime UPDATE tiba lebih dulu → likeCount lokal = 1.
--   3) RPC selesai → FE baca cur = 1 → set likeCount = cur + 1 = 2.  ❌
--
-- Perbaikan: RPC mengembalikan like_count ABSOLUT (dibaca setelah
-- trigger selesai di transaksi yang sama), jadi FE bisa memakai nilai
-- server sebagai sumber kebenaran — idempotent terhadap realtime.
-- Pola ini sama dengan toggle_story_like yang sudah benar.
--
-- ⚠️ CARA APPLY: via Supabase Dashboard → SQL Editor (sama seperti
--    pola migration lain di repo ini).
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. toggle_post_like — kembalikan like_count absolut
-- ──────────────────────────────────────────────
create or replace function public.toggle_post_like(p_post_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  liked boolean;
  v_count int;
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
  -- Baca ulang counter yang sudah di-update trigger dalam transaksi yang
  -- sama → nilai konsisten & absolut (tidak bergantung hitung lokal FE).
  select like_count into v_count from public.posts where id = p_post_id;
  return jsonb_build_object('ok', true, 'liked', liked, 'likeCount', coalesce(v_count, 0));
end; $$;
revoke execute on function public.toggle_post_like(uuid) from public, anon;
grant execute on function public.toggle_post_like(uuid) to authenticated;

-- ──────────────────────────────────────────────
-- 2. toggle_comment_like — kembalikan like_count absolut
-- ──────────────────────────────────────────────
create or replace function public.toggle_comment_like(p_comment_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  liked boolean;
  v_count int;
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
  select like_count into v_count from public.post_comments where id = p_comment_id;
  return jsonb_build_object('ok', true, 'liked', liked, 'likeCount', coalesce(v_count, 0));
end; $$;
revoke execute on function public.toggle_comment_like(bigint) from public, anon;
grant execute on function public.toggle_comment_like(bigint) to authenticated;
