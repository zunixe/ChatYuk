-- ============================================================
-- ChatYuk: Admin hapus chat + opsi hapus user
-- - Hapus SEMUA history private_messages chat + private_chats
-- - Ambil daftar path foto di bucket (untuk cleanup storage di client)
-- - Opsional hapus user dari DB (kecuali admin zunixe@gmail.com)
-- Dipanggil oleh admin (RLS security definer).
-- ============================================================

create or replace function public.admin_delete_chat(
  p_chat_id text,
  p_delete_user_ids uuid[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_email text := coalesce(auth.email(),'');
  photo_paths jsonb := '[]'::jsonb;
  uid uuid;
begin
  if admin_email != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  -- Kumpulkan path foto (chat/.../x.jpg) untuk cleanup bucket di client.
  select coalesce(jsonb_agg(image_data), '[]'::jsonb) into photo_paths
  from private_messages
  where chat_id = p_chat_id
    and image_data like 'chat/%';

  -- Hapus semua pesan chat.
  delete from public.private_messages where chat_id = p_chat_id;

  -- Hapus chat.
  delete from public.private_chats where chat_id = p_chat_id;

  -- Hapus user yang diceklis (kecuali admin).
  foreach uid in array p_delete_user_ids loop
    -- Skip jika user adalah admin (zunixe@gmail.com)
    if exists (
      select 1 from auth.users where id = uid and email = 'zunixe@gmail.com'
    ) then
      continue;
    end if;
    -- Hapus data terkait user.
    delete from public.room_presence where user_id = uid;
    delete from public.blocks where blocker_id = uid or blocked_id = uid;
    delete from public.reports where reporter_id = uid or reported_id = uid;
    delete from public.user_photos where user_id = uid;
    delete from public.private_chats where uid = any (participants);
    delete from public.private_messages where sender_id = uid;
    delete from public.profiles where id = uid;
    delete from auth.users where id = uid;
  end loop;

  return jsonb_build_object('ok', true, 'photo_paths', photo_paths);
end;
$$;

revoke execute on function public.admin_delete_chat(text, uuid[]) from public, anon;
grant execute on function public.admin_delete_chat(text, uuid[]) to authenticated, service_role;
