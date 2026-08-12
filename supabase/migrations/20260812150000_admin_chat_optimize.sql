-- ============================================================
-- ChatYuk: Optimasi Admin Chat View
-- - admin_get_chat_messages: exclude image_data untuk foto biasa
--   (ringan — load lazy via PhotoCache di client), view-once
--   image_data tetap utuh (admin perlu lihat).
-- - admin_get_message_image: fetch satu image_data untuk retry
--   foto gagal + view-once admin viewing.
-- ============================================================

-- 1. Update admin_get_chat_messages — exclude image_data untuk image biasa
create or replace function public.admin_get_chat_messages(p_chat_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'chat_id', m.chat_id,
      'sender_id', m.sender_id,
      'sender_name', m.sender_name,
      'sender_gender', m.sender_gender,
      'text', m.text,
      'type', m.type,
      -- Foto biasa: image_data kosongkan (load lazy via PhotoCache).
      -- View-once: image_data tetap utuh (admin perlu lihat expired).
      'image_data', case
        when m.type in ('view_once','view_once_expired') then m.image_data
        else ''
      end,
      'created_at', m.created_at,
      'replied_to_id', m.replied_to_id,
      'replied_to_text', m.replied_to_text,
      'replied_to_sender_name', m.replied_to_sender_name
    ) order by m.created_at asc
  ), '[]'::jsonb) into result
  from private_messages m
  where m.chat_id = p_chat_id;

  return result;
end;
$$;
revoke execute on function public.admin_get_chat_messages(text) from public, anon;
grant execute on function public.admin_get_chat_messages(text) to authenticated, service_role;

-- 2. admin_get_message_image — fetch satu image_data untuk retry foto
create or replace function public.admin_get_message_image(p_message_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  result text;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select m.image_data into result
  from private_messages m
  where m.id = p_message_id;

  return result;
end;
$$;
revoke execute on function public.admin_get_message_image(bigint) from public, anon;
grant execute on function public.admin_get_message_image(bigint) to authenticated, service_role;
