-- ============================================================
-- ChatYuk: Pagination Admin Chat Monitor
-- - admin_list_chats: limit/offset + total count → monitor chat
--   ringan walau banyak percakapan.
-- - admin_get_chat_messages: limit/offset → buka chat tidak
--   memuat ribuan pesan sekaligus.
-- NOTE: fungsi lama tanpa pagination DI-DROP supaya tidak terjadi
-- overload PostgREST (ambigu saat resolve function).
-- ============================================================

-- Drop overload lama (fungsi tanpa pagination)
drop function if exists public.admin_list_chats();
drop function if exists public.admin_get_chat_messages(text);

-- 1. List chats dengan pagination + total
create or replace function public.admin_list_chats(
  p_limit int default 50,
  p_offset int default 0
)
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

  select jsonb_build_object(
    'total', (select count(*) from private_chats c
              where c.last_message_at is not null
                 or exists (select 1 from private_messages m where m.chat_id = c.chat_id)),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'chat_id', c.chat_id,
        'participants', c.participants,
        'participant_names', c.participant_names,
        'last_message', c.last_message,
        'last_message_at', c.last_message_at,
        'message_count', (select count(*) from private_messages m where m.chat_id = c.chat_id)
      ) order by c.last_message_at desc
    ), '[]'::jsonb)
  ) into result
  from (
    select c.*
    from private_chats c
    where c.last_message_at is not null
       or exists (select 1 from private_messages m where m.chat_id = c.chat_id)
    order by c.last_message_at desc
    limit p_limit offset p_offset
  ) c;

  return result;
end;
$$;
revoke execute on function public.admin_list_chats(int, int) from public, anon;
grant execute on function public.admin_list_chats(int, int) to authenticated, service_role;

-- 2. Get messages dengan pagination (desc dari terbaru)
drop function if exists public.admin_get_chat_messages(text);
create or replace function public.admin_get_chat_messages(
  p_chat_id text,
  p_limit int default 100,
  p_offset int default 0
)
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
    ) order by m.created_at desc
  ), '[]'::jsonb) into result
  from private_messages m
  where m.chat_id = p_chat_id
  order by m.created_at desc
  limit p_limit offset p_offset;

  return result;
end;
$$;
revoke execute on function public.admin_get_chat_messages(text, int, int) from public, anon;
grant execute on function public.admin_get_chat_messages(text, int, int) to authenticated, service_role;
