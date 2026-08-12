-- ── ADMIN CHAT MONITOR ─────────────────────────────────────────────
-- Admin (zunixe@gmail.com) dapat melihat semua percakapan private user.
-- Fungsi security definer + cek email admin → bypass RLS participant.

-- List semua private chats (dengan info participant + pesan terakhir)
create or replace function public.admin_list_chats()
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
      'chat_id', c.chat_id,
      'participants', c.participants,
      'participant_names', c.participant_names,
      'last_message', c.last_message,
      'last_message_at', c.last_message_at,
      'message_count', (select count(*) from private_messages m where m.chat_id = c.chat_id)
    ) order by c.last_message_at desc
  ), '[]'::jsonb) into result
  from private_chats c
  where c.last_message_at is not null
     or exists (select 1 from private_messages m where m.chat_id = c.chat_id);

  return result;
end;
$$;
revoke execute on function public.admin_list_chats() from public, anon;
grant execute on function public.admin_list_chats() to authenticated, service_role;

-- Ambil semua pesan satu chat (termasuk image_data view-once, terbuka utk admin)
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
      'image_data', m.image_data,
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
