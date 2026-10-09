-- ============================================================
-- Fitur: GANTI IKON/AVATAR GRUP (owner/admin).
--
-- Belum ada jalur update icon room. RPC ini:
--   - hanya OWNER (rooms.owner_id = auth.uid()) ATAU admin grup
--     (fn_room_role = 'owner'/'admin') yang boleh.
--   - menulis rooms.icon (emoji ATAU path `room-icons/...`).
--   - validasi ringan: tidak kosong & panjang wajar.
-- ============================================================

create or replace function public.update_room_icon(p_room_id text, p_icon text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_role text;
  v_icon text := btrim(coalesce(p_icon, ''));
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'unauthenticated');
  end if;
  if p_room_id is null or btrim(p_room_id) = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_room');
  end if;
  if v_icon = '' or length(v_icon) > 512 then
    return jsonb_build_object('ok', false, 'reason', 'bad_icon');
  end if;

  select owner_id into v_owner from public.rooms where id = p_room_id;
  if v_owner is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  v_role := public.fn_room_role(v_uid, p_room_id);
  if v_uid <> v_owner and coalesce(v_role, '') not in ('owner', 'admin') then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;

  update public.rooms set icon = v_icon where id = p_room_id;
  return jsonb_build_object('ok', true, 'icon', v_icon);
end;
$$;

revoke execute on function public.update_room_icon(text, text) from public, anon;
grant execute on function public.update_room_icon(text, text) to authenticated;
