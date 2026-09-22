-- ============================================================
-- story_tray: hormati privacy story + profile_photo.
--
-- LATAR (audit 2026-09-22):
--   story_tray TIDAK memanggil privacy_can_view(author,'story') — hanya
--   story_slides yang memanggilnya. Akibatnya bila user set story =
--   'nobody'/'friends_except', avatar + jumlah slide-nya TETAP muncul di
--   tray orang lain (kebocoran metadata walau isi slide kosong saat dibuka).
--   Selain itu avatar di tray diambil mentah dari profiles → bypass
--   profile_photo_visibility.
--
-- PERBAIKAN:
--   - Tambah filter: hanya author yang privacy_can_view(...,'story') = true.
--   - Avatar di-mask sesuai profile_photo_visibility.
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================
create or replace function public.story_tray()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  select coalesce(jsonb_agg(t.obj order by t.sort_own desc, t.sort_unseen desc, t.latest_at desc), '[]'::jsonb)
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
        'has_unseen', a.unseen_count > 0,
        'own', a.author_id = auth.uid()
      ) as obj,
      (a.author_id = auth.uid()) as sort_own,
      (a.unseen_count > 0) as sort_unseen,
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
$fn$;

revoke execute on function public.story_tray() from public, anon;
grant execute on function public.story_tray() to authenticated;
