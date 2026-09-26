-- ============================================================
-- Story VIDEO pendek (maks 15 dtk, polos tanpa teks overlay).
--
-- - Kolom baru: media_type ('image'|'video'), video_path, duration_ms.
-- - create_story: 3 param baru (defaults) + validasi video (path
--   story/, durasi 1..15000ms). Signature lama tetap jalan.
-- - story_slides/story_tray: kirim kolom baru (tray thumb tetap image;
--   tile video fallback inisial sampai ada poster).
-- - Policy Storage tidak perlu diubah (bucket+owner, agnostik ekstensi).
-- - Limit 10 slide/hari (RLS) + purge expired tidak berubah.
-- menyentuh: create_story
-- menyentuh: story_slides
-- menyentuh: story_tray
-- ============================================================

alter table public.stories
  add column if not exists media_type text not null default 'image';
alter table public.stories
  add column if not exists video_path text not null default '';
alter table public.stories
  add column if not exists duration_ms int not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'stories_media_type_check'
  ) then
    alter table public.stories
      add constraint stories_media_type_check
      check (media_type in ('image', 'video'));
  end if;
end $$;

-- Hapus overload lama (10 arg) — dua overload bikin PostgREST 300
-- Multiple Choices untuk panggilan parsial (insiden admin_set_dummy_ai).
drop function if exists public.create_story(text, text, real, real, integer, integer, boolean, real, real, text);

create or replace function public.create_story(p_image_path text, p_text_overlay text default ''::text, p_text_x real default 0.5, p_text_y real default 0.85, p_text_color integer default 0, p_text_size integer default 1, p_text_bg boolean default false, p_text_scale real default 1.0, p_text_rotation real default 0, p_visibility text default 'followers'::text, p_media_type text default 'image'::text, p_video_path text default ''::text, p_duration_ms integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_vis text;
  v_media text;
begin
  if not public._viewer_is_registered() then
    v_vis := 'everyone';
  elsif p_visibility not in ('everyone','followers','friends') then
    if p_visibility = 'registered' then
      v_vis := 'followers';
    else
      raise exception 'Visibility tidak valid';
    end if;
  else
    v_vis := p_visibility;
  end if;
  if length(coalesce(p_text_overlay, '')) > 300 then
    raise exception 'Teks terlalu panjang (max 300)';
  end if;
  v_media := coalesce(p_media_type, 'image');
  if v_media not in ('image', 'video') then
    raise exception 'Media tidak valid';
  end if;
  if v_media = 'video' then
    if coalesce(p_video_path, '') = ''
       or p_video_path not like 'story/%' then
      raise exception 'Video path tidak valid';
    end if;
    if coalesce(p_duration_ms, 0) < 1000
       or coalesce(p_duration_ms, 0) > 15000 then
      raise exception 'Durasi video 1-15 detik';
    end if;
  end if;
  insert into public.stories (
    author_id, author_name, image_path, text_overlay, text_x, text_y,
    text_color, text_size, text_bg, text_scale, text_rotation, visibility,
    media_type, video_path, duration_ms
  )
  select auth.uid(),
         coalesce((select nickname from public.profiles where id = auth.uid()), 'Anon'),
         p_image_path, coalesce(p_text_overlay, ''),
         greatest(least(coalesce(p_text_x, 0.5), 1), 0),
         greatest(least(coalesce(p_text_y, 0.85), 1), 0),
         greatest(least(coalesce(p_text_color, 0), 7), 0),
         greatest(least(coalesce(p_text_size, 1), 2), 0),
         coalesce(p_text_bg, false),
         greatest(coalesce(p_text_scale, 1.0), 0.1),
         coalesce(p_text_rotation, 0),
         v_vis,
         v_media, coalesce(p_video_path, ''),
         greatest(coalesce(p_duration_ms, 0), 0)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

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
    'visibility', s.visibility,
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
      s.author_id = auth.uid()
      or ((s.visibility = 'everyone')
        or (s.visibility = 'followers' and exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = s.author_id))
        or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))
      and not exists (select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id) or (b.blocker_id = s.author_id and b.blocked_id = auth.uid()))
    );
  return result;
end;
$function$;

create or replace function public.story_tray()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
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
        'has_video', a.has_video
      ) as obj,
      (a.author_id = auth.uid()) as sort_own,
      coalesce(a.muted, false) as sort_muted,
      (a.unseen_count > 0 and not coalesce(a.muted, false)) as sort_unseen,
      a.latest_at
    from (
      select s.author_id,
             max(s.author_name) as author_name,
             -- Avatar di-mask sesuai profile_photo_visibility (bukan mentah).
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
        -- Privacy story: author yang menutup story-nya tidak muncul di tray.
        and public.privacy_can_view(s.author_id, 'story', auth.uid())
        and (
          s.author_id = auth.uid()
          or (
            (s.visibility = 'everyone')
            or (s.visibility = 'followers' and exists (
                  select 1 from public.follows f
                  where f.follower_id = auth.uid()
                    and f.followee_id = s.author_id))
            or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id))
          )
          and not exists (
            select 1 from public.blocks b
            where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
               or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
          )
        )
      group by s.author_id
    ) a
  ) t;
  return result;
end;
$function$;
