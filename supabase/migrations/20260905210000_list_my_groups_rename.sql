-- ============================================================
-- Konsistensi penamaan grup: RPC list_my_private_rooms → list_my_groups.
-- Body identik (grup milikku = is_private + member). RPC lama di-drop
-- supaya tidak ada dua sumber kebenaran.
-- ============================================================

drop function if exists public.list_my_private_rooms(uuid);

create or replace function public.list_my_groups(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
  from public.rooms r
  where r.is_private = true
    and exists (select 1 from public.room_members m where m.room_id = r.id and m.user_id = p_uid);
$fn$;

revoke execute on function public.list_my_groups(uuid) from public, anon;
grant execute on function public.list_my_groups(uuid) to authenticated;
