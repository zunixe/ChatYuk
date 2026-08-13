-- ============================================================
-- ChatYuk: admin_list_chats_page + info admin (untuk delete dialog)
-- Tambah field participant_emails + admin_uids agar client tahu
-- user mana yang admin (tidak bisa dihapus) di dialog delete chat.
-- ============================================================

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
    'admin_uids', coalesce((
      select jsonb_agg(id) from auth.users where email = 'zunixe@gmail.com'
    ), '[]'::jsonb),
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
