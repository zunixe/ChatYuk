-- ============================================================
-- STORY: REVISI — semua "hapus" (user MAUPUN admin) = PRIVATE
-- (owner_only = true). TIDAK ADA hard-delete via delete_story.
--
-- REVISI dari 20261006150000 (yang bikin admin hard-delete): user memutuskan
-- story yang dihapus (termasuk yang oleh ADMIN, mis. kasus nude) tetap
-- disimpan sebagai PRIVATE — pembuat (jason) DAN admin tetap bisa lihat,
-- orang lain tidak. Tidak ada konten yang hilang permanen via RPC ini.
--
-- (Purge permanen tetap ada di cron `purge_expired_stories` setelah 24 jam —
--  kebijakan retensi story, bukan aksi hapus.)
-- ============================================================

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
  -- Semua "hapus" (user sendiri MAUPUN admin) = jadikan PRIVATE (owner_only).
  -- Pembuat & admin tetap lihat; orang lain tidak. Tidak ada yang hilang.
  update public.stories set owner_only = true where id = p_story_id;
  return jsonb_build_object('ok', true, 'image_path', v_path);
end;
$fn$;

revoke execute on function public.delete_story(uuid) from public, anon;
grant execute on function public.delete_story(uuid) to authenticated;
