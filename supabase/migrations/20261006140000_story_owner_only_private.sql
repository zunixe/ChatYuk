-- ============================================================
-- STORY: hapus-slide → jadikan PRIVATE "hanya saya" (owner_only),
-- + admin bisa lihat SEMUA (termasuk yang owner_only) dengan keterangan.
--
-- LATAR:
--   Dulu `delete_story` menghapus PERMANEN row. User ingin "hapus" =
--   slide disembunyikan dari orang lain TAPI tetap bisa dilihat pembuat
--   sendiri (mis. arsip pribadi). Admin tetap bisa memoderasi (lihat semua).
--
-- DESAIN:
--   - Kolom baru `stories.owner_only boolean not null default false`.
--     true  = slide PRIVATE: hanya author (auth.uid() = author_id) yang
--             boleh melihat via story_slides/story_tray.
--   - `delete_story` TIDAK hapus row lagi → set owner_only = true.
--     (Return `ok`, dan `image_path` untuk kompatibilitas client lama yang
--     memakainya membersihkan file — tapi file TIDAK dihapus karena slide
--     masih dipakai pemilik. Client baru tidak menghapus file.)
--   - `story_slides`/`story_tray`: sertakan `owner_only` + ADMIN bypass
--     (is_admin_request) supaya admin lihat semua + tahu statusnya.
--   - RPC baru `admin_story_all()` untuk admin: daftar SEMUA story aktif
--     lintas author + flag owner_only/visibility (keterangan).
-- ============================================================

-- 1) Kolom owner_only
alter table public.stories
  add column if not exists owner_only boolean not null default false;

create index if not exists idx_stories_owner_only on public.stories(owner_only);

-- 2) delete_story → privatkan (owner_only = true), bukan hapus.
create or replace function public.delete_story(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_path text;
begin
  select image_path into v_path from public.stories
  where id = p_story_id
    and (author_id = auth.uid() or public.is_admin_request());
  if v_path is null then
    raise exception 'Unauthorized';
  end if;
  -- "Hapus" = jadikan PRIVATE (hanya author lihat). Admin juga tetap lihat.
  update public.stories set owner_only = true where id = p_story_id;
  return jsonb_build_object('ok', true, 'image_path', v_path);
end;
$fn$;

-- 3) story_slides — owner_only + admin bypass.
create or replace function public.story_slides(p_author uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'image_path', s.image_path, 'text_overlay', s.text_overlay,
    'text_x', s.text_x, 'text_y', s.text_y, 'text_color', s.text_color,
    'text_size', s.text_size, 'text_scale', s.text_scale,
    'text_rotation', s.text_rotation, 'text_bg', s.text_bg,
    'visibility', s.visibility, 'owner_only', s.owner_only,
    'media_type', s.media_type, 'video_path', s.video_path,
    'duration_ms', s.duration_ms,
    'like_count', (select count(*) from public.story_likes l where l.story_id = s.id),
    'liked', exists (select 1 from public.story_likes l where l.story_id = s.id and l.user_id = auth.uid()),
    'created_at', s.created_at
  ) order by s.created_at asc), '[]'::jsonb) into result
  from public.stories s
  where s.author_id = p_author and s.expires_at > now()
    and public.privacy_can_view(s.author_id, 'story', auth.uid())
    and (
      -- Admin lihat SEMUA (termasuk owner_only) — untuk moderasi.
      public.is_admin_request()
      -- Author lihat miliknya sendiri (termasuk yang owner_only).
      or s.author_id = auth.uid()
      -- Lain: hormati owner_only + visibility + blokir.
      or (
        not s.owner_only
        and ((s.visibility = 'everyone')
          or (s.visibility = 'followers' and exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = s.author_id))
          or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))
        and not exists (select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id) or (b.blocker_id = s.author_id and b.blocked_id = auth.uid()))
      )
    );
  return result;
end;
$function$;

-- 4) story_tray — owner_only + admin bypass.
create or replace function public.story_tray()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  v_admin boolean := public.is_admin_request();
begin
  select coalesce(jsonb_agg(t.obj order by t.sort_own desc, t.sort_muted asc, t.sort_unseen desc, t.latest_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'author_id', a.author_id,
        'author_name', a.author_name,
        'avatar', a.avatar,
        'is_registered', a.is_registered,
        'slide_count', a.slide_count,
        'thumb_path', a.thumb_path,
        'has_unseen', a.unseen_count > 0 and not a.muted,
        'own', a.author_id = auth.uid(),
        'muted', a.muted,
        'has_video', a.has_video,
        'has_owner_only', a.has_owner_only
      ) as obj,
      (a.author_id = auth.uid()) as sort_own,
      coalesce(a.muted, false) as sort_muted,
      (a.unseen_count > 0 and not coalesce(a.muted, false)) as sort_unseen,
      a.latest_at
    from (
      select s.author_id,
             max(s.author_name) as author_name,
             case when public.privacy_can_view(s.author_id, 'profile_photo', auth.uid())
                  then (select avatar from public.profiles p where p.id = s.author_id)
                  else '' end as avatar,
             (select is_registered from public.profiles p where p.id = s.author_id) as is_registered,
             count(*) as slide_count,
             (select s2.image_path from public.stories s2
              where s2.author_id = s.author_id and s2.expires_at > now()
              order by s2.created_at desc limit 1) as thumb_path,
             max(s.created_at) as latest_at,
             bool_or(s.media_type = 'video') as has_video,
             bool_or(s.owner_only) as has_owner_only,
             exists (
               select 1 from public.story_mutes m
               where m.muter_id = auth.uid() and m.muted_id = s.author_id
             ) as muted,
             count(*) filter (
               where not exists (
                 select 1 from public.story_views v
                 where v.story_id = s.id and v.viewer_id = auth.uid()
               )
             ) as unseen_count
      from public.stories s
      where s.expires_at > now()
        -- Admin lihat semua author (moderasi); user hormati privacy author.
        and (v_admin or public.privacy_can_view(s.author_id, 'story', auth.uid()))
        and (
          v_admin
          or s.author_id = auth.uid()
          or (
            not s.owner_only
            and ((s.visibility = 'everyone')
              or (s.visibility = 'followers' and exists (
                    select 1 from public.follows f
                    where f.follower_id = auth.uid()
                      and f.followee_id = s.author_id))
              or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))
            and not exists (
              select 1 from public.blocks b
              where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
                 or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
            )
          )
        )
      group by s.author_id
    ) a
  ) t;
  return result;
end;
$function$;

-- 5) admin_story_all() — daftar SEMUA slide aktif (moderasi) + keterangan.
--    Hanya admin. Return array {id, author_id, author_name, slide status}.
create or replace function public.admin_story_all(p_limit int default 200)
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
    'image_path', s.image_path,
    'media_type', s.media_type,
    'owner_only', s.owner_only,
    'visibility', s.visibility,
    'created_at', s.created_at,
    'expires_at', s.expires_at
  ) order by s.created_at desc), '[]'::jsonb)
  into result
  from (
    select * from public.stories
    where expires_at > now()
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  ) s;
  return result;
end;
$fn$;

revoke execute on function public.admin_story_all(int) from public, anon;
grant execute on function public.admin_story_all(int) to authenticated;
