-- ============================================================
-- FITUR: tampilkan visibilitas story yang sudah diposting
--
-- RPC story_slides sebelumnya TIDAK mengirim kolom visibility —
-- field di model client selalu fallback 'registered', sehingga owner
-- tidak bisa tahu story-nya tayang untuk Semua orang / Pengikut / Teman.
--
-- Fix: sertakan 'visibility' di payload slide (SELECT saja, tidak ada
-- perubahan kebijakan akses).
-- ============================================================

create or replace function public.story_slides(p_author uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'image_path', s.image_path,
    'text_overlay', s.text_overlay,
    'text_x', s.text_x,
    'text_y', s.text_y,
    'text_color', s.text_color,
    'text_size', s.text_size,
    'text_bg', s.text_bg,
    'visibility', s.visibility,
    'created_at', s.created_at
  ) order by s.created_at asc), '[]'::jsonb)
  into result
  from public.stories s
  where s.author_id = p_author
    and s.expires_at > now()
    and (
      s.author_id = auth.uid()
      or (
        (s.visibility = 'everyone')
        or (s.visibility = 'registered' and public._viewer_is_registered())
        or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id))
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
           or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
      )
    );
  return result;
end;
$fn$;

revoke execute on function public.story_slides(uuid) from public, anon;
grant execute on function public.story_slides(uuid) to authenticated;
