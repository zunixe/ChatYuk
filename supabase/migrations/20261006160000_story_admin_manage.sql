-- ============================================================
-- ADMIN: kelola STORY — lihat semua slide, atur visibility, hapus permanen.
--
-- Kebutuhan admin panel (tab "Story"):
--   1) Lihat SEMUA slide story aktif lintas user (terbaru di atas) + info
--      visibilitas (public/followers/friends/private) untuk siapa story itu.
--   2) Atur visibility slide user: public / followers / friends / private.
--   3) Hapus PERMANEN (moderasi, mis. nude).
--
-- Mapping visibilitas:
--   public    → visibility='everyone',  owner_only=false
--   followers → visibility='followers', owner_only=false
--   friends   → visibility='friends',   owner_only=false
--   private   → owner_only=true (visibility dipertahankan agar bisa dibalik)
-- ============================================================

-- 1) admin_story_all — semua slide aktif + filter visibilitas.
create or replace function public.admin_story_all(
  p_limit int default 200,
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
    'id', s.id,
    'author_id', s.author_id,
    'author_name', s.author_name,
    'author_avatar', case
        when public.privacy_can_view(s.author_id, 'profile_photo', auth.uid())
        then coalesce((select avatar from public.profiles p where p.id = s.author_id), '')
        else '' end,
    'image_path', s.image_path,
    'media_type', s.media_type,
    'video_path', s.video_path,
    'duration_ms', s.duration_ms,
    'owner_only', s.owner_only,
    'visibility', s.visibility,
    'like_count', (select count(*) from public.story_likes l where l.story_id = s.id),
    'created_at', s.created_at,
    'expires_at', s.expires_at
  ) order by s.created_at desc), '[]'::jsonb)
  into result
  from (
    select * from public.stories s
    where s.expires_at > now()
      and (
        coalesce(p_filter, 'all') = 'all'
        or (p_filter = 'private'   and s.owner_only)
        or (p_filter = 'public'    and not s.owner_only and s.visibility = 'everyone')
        or (p_filter = 'followers' and not s.owner_only and s.visibility = 'followers')
        or (p_filter = 'friends'   and not s.owner_only and s.visibility = 'friends')
      )
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  ) s;
  return result;
end;
$fn$;

-- 2) admin_set_story_visibility — atur visibilitas satu slide.
create or replace function public.admin_set_story_visibility(
  p_story_id uuid,
  p_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_exists boolean;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if p_state not in ('public','followers','friends','private') then
    raise exception 'State visibilitas tidak valid';
  end if;
  select exists(select 1 from public.stories where id = p_story_id)
    into v_exists;
  if not v_exists then
    raise exception 'Story tidak ditemukan';
  end if;

  if p_state = 'private' then
    update public.stories set owner_only = true where id = p_story_id;
  else
    update public.stories
      set owner_only = false,
          visibility = case p_state
            when 'public' then 'everyone'
            when 'followers' then 'followers'
            when 'friends' then 'friends'
          end
      where id = p_story_id;
  end if;

  return jsonb_build_object('ok', true, 'state', p_state);
end;
$fn$;

-- 3) admin_story_delete — hapus PERMANEN (moderasi). Return image_path agar
--    client membersihkan file Storage.
create or replace function public.admin_story_delete(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_path text;
  v_video text;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select image_path, coalesce(video_path, '')
    into v_path, v_video
  from public.stories where id = p_story_id;
  if v_path is null then
    raise exception 'Story tidak ditemukan';
  end if;
  delete from public.stories where id = p_story_id;
  return jsonb_build_object('ok', true, 'image_path', v_path, 'video_path', v_video);
end;
$fn$;

revoke execute on function public.admin_story_all(int, text) from public, anon;
grant execute on function public.admin_story_all(int, text) to authenticated;
revoke execute on function public.admin_set_story_visibility(uuid, text) from public, anon;
grant execute on function public.admin_set_story_visibility(uuid, text) to authenticated;
revoke execute on function public.admin_story_delete(uuid) from public, anon;
grant execute on function public.admin_story_delete(uuid) to authenticated;
