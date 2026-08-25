-- ChatYuk: admin chat monitor — jangan jadikan pesan type 'call' sebagai
-- penentu urutan. Saat call berlangsung, pin dilakukan client-side via
-- activeCallsByChat (ke atas seperti pinned). Setelah selesai, urutan
-- kembali ke waktu pesan terakhir BUKAN call (text/image/view_once).

create or replace function public.admin_list_chats_page(p_limit integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
        'last_message_at', c.effective_last,
        'message_count', c.msg_count
      ) order by c.effective_last desc nulls last
    ), '[]'::jsonb)
  ) into result
  from (
    select
      c.*,
      (select count(*) from private_messages m where m.chat_id = c.chat_id) as msg_count,
      coalesce(
        (select max(m.created_at) from private_messages m where m.chat_id = c.chat_id and coalesce(m.type,'text') != 'call'),
        c.last_message_at
      ) as effective_last
    from private_chats c
    where c.last_message_at is not null
       or exists (select 1 from private_messages m where m.chat_id = c.chat_id)
    order by effective_last desc nulls last
    limit p_limit offset p_offset
  ) c;

  return result;
end;
$function$;

revoke execute on function public.admin_list_chats_page(integer, integer) from public, anon;
grant execute on function public.admin_list_chats_page(integer, integer) to authenticated, service_role;
