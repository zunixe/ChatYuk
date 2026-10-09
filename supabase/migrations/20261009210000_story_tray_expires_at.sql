-- ============================================================
-- story_tray: kirim `expires_at` (max) per author.
--
-- LATAR (bug 2026-10-09): saat cold start, tray story NGEBLINK — story lama
-- (sudah expired) tampil sekejap dari cache disk, lalu hilang setelah server
-- refresh (server sudah filter expires_at > now(), jadi cache-lah yang basi).
-- Client perlu tahu masa berlaku tiap author untuk MENGOSONGKAN cache expired
-- tanpa menampilkannya (lihat lib/providers/riverpod/story_provider.dart).
--
-- Perubahan: tambah 'expires_at' = max(s.expires_at) per author di dalam
-- jsonb_build_object. Semua logika lain TIDAK berubah.
--
-- Idempotent (create or replace). Tidak menyentuh fungsi FROZEN.
-- CARA APPLY: Management API POST /v1/projects/{ref}/database/query.
-- ============================================================

create or replace function public.story_tray()
returns jsonb
language plpgsql
stable
security definer
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
        'has_owner_only', a.has_owner_only,
        'expires_at', a.expires_at
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
             max(s.expires_at) as expires_at,
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
