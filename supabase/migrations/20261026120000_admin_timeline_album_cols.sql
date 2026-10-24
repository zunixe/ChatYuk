-- ============================================================
-- ChatYuk: admin_timeline_all — sertakan kolom media album
--
-- Tab Timeline admin menampilkan kartu lewat [PostCard] yang SAMA dengan
-- Timeline utama, jadi butuh `images`/`image_w`/`image_h`/`image_dims`/
-- `image_blurhashes` untuk post multi-foto. Migrasi lama
-- (20261011170000_admin_timeline.sql) hanya mengirim image_path → post
-- album tampil kosong/sebagian di panel admin.
--
-- Aditif: nama fungsi & signature SAMA, hanya menambah kunci JSON.
-- ============================================================

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
    'images', p.images,
    'image_w', p.image_w,
    'image_h', p.image_h,
    'image_dims', p.image_dims,
    'image_blurhashes', p.image_blurhashes,
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
