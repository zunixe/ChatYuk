-- ============================================================
-- ChatYuk: Konsolidasi RPC Admin Chat Monitor
-- Kode app (admin_service.dart) memanggil RPC:
--   - admin_list_chats_page(p_limit, p_offset)
--   - admin_get_chat_messages_page(p_chat_id, p_limit, p_offset)
-- Tapi migration sebelumnya membuat nama TANPA suffix "_page".
-- Migration ini (idempotent via create or replace) membuat fungsi
-- "_page" yang sesuai kode app, sekaligus drop overload lama agar
-- tidak ambigu.
-- ============================================================

-- Hapus overload lama yang mungkin masih ada (tanpa _page)
drop function if exists public.admin_list_chats();
drop function if exists public.admin_list_chats(int, int);
drop function if exists public.admin_get_chat_messages(text);
drop function if exists public.admin_get_chat_messages(text, int, int);

-- 1. List chats (pagination) — versi _page
create or replace function public.admin_list_chats_page(
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
revoke execute on function public.admin_list_chats_page(int, int) from public, anon;
grant execute on function public.admin_list_chats_page(int, int) to authenticated, service_role;

-- 2. Get chat messages (pagination) — versi _page
create or replace function public.admin_get_chat_messages_page(
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
  from (
    select m.*
    from private_messages m
    where m.chat_id = p_chat_id
    order by m.created_at desc
    limit p_limit offset p_offset
  ) m;

  return result;
end;
$$;
revoke execute on function public.admin_get_chat_messages_page(text, int, int) from public, anon;
grant execute on function public.admin_get_chat_messages_page(text, int, int) to authenticated, service_role;
