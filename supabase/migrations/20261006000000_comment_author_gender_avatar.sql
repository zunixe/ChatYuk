-- ============================================================
-- ChatYuk — Komentar timeline: sertakan gender + avatar author.
--
-- Tujuan: avatar komentar di timeline bisa tampil seperti daftar
-- "Pengguna Online" — foto asli + ring warna gender (male=biru,
-- female=pink). Sebelumnya RPC hanya mengirim authorId/authorName
-- sehingga UI terpaksa pakai inisial polos tanpa foto/gender.
--
-- Sumber: kolom profiles.gender + profiles.avatar (JOIN by author_id).
-- Idempotent (create or replace). Semantik hasil lain TIDAK berubah.
-- ============================================================

create or replace function public.list_post_comments(p_post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare me uuid := auth.uid(); rows jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'postId', c.post_id,
      'authorId', c.author_id,
      'authorName', c.author_name,
      'authorGender', coalesce(pr.gender, ''),
      'authorAvatar', coalesce(pr.avatar, ''),
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
  left join public.profiles pr on pr.id = c.author_id
  where c.post_id = p_post_id;
  return rows;
end; $function$;
