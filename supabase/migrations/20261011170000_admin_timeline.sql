-- Admin: kelola TIMELINE (menu baru di panel admin).
--
-- Tujuan:
--   1. `admin_timeline_all` — daftar SEMUA post (public/followers/subscribers)
--      TANPA dibatasi RLS `posts_select` (admin lihat lintas user).
--   2. `admin_set_post_visibility` — ubah visibilitas post siapa pun
--      (mis. public → subscribers/followers) untuk moderasi.
--
-- Pola identik admin_story_all/admin_set_story_visibility: security definer +
-- guard is_admin_request(), revoke dari public/anon.

-- ──────────────────────────────────────────────
-- 1. Daftar semua post (lintas user, tanpa RLS)
-- ──────────────────────────────────────────────
create or replace function public.admin_timeline_all(
  p_limit int default 100,
  p_filter text default 'all'
)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $fn$
declare result jsonb;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'author_id', p.author_id,
    'author_name', p.author_name,
    'author_gender', p.author_gender,
    'text', p.text,
    'image_path', p.image_path,
    'visibility', p.visibility,
    'like_count', p.like_count,
    'comment_count', p.comment_count,
    'share_count', p.share_count,
    'is_boosted', p.is_boosted,
    'created_at', p.created_at
  ) order by p.created_at desc), '[]'::jsonb)
  into result
  from (
    select * from public.posts
    where coalesce(p_filter, 'all') = 'all'
       or visibility = p_filter
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) p;
  return result;
end;
$fn$;

revoke execute on function public.admin_timeline_all(int, text) from public, anon;
grant execute on function public.admin_timeline_all(int, text) to authenticated;

-- ──────────────────────────────────────────────
-- 2. Ubah visibilitas satu post (moderasi)
-- ──────────────────────────────────────────────
create or replace function public.admin_set_post_visibility(
  p_post_id uuid,
  p_visibility text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_id uuid;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  -- Nilai valid sama dengan CHECK constraint tabel posts.
  if coalesce(p_visibility, '') not in ('public', 'followers', 'subscribers') then
    raise exception 'Invalid visibility';
  end if;
  update public.posts
     set visibility = p_visibility
   where id = p_post_id
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'visibility', p_visibility);
end;
$fn$;

revoke execute on function public.admin_set_post_visibility(uuid, text) from public, anon;
grant execute on function public.admin_set_post_visibility(uuid, text) to authenticated;
