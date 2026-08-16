-- ============================================================
-- ChatYuk: admin_list_chats_page — urutkan berdasarkan waktu pesan
-- terakhir yang SEBENARNYA (samakan dengan urutan Private Chat user).
-- Sebelumnya urut c.last_message_at saja, yang kadang tidak sinkron
-- dengan pesan terakhir. Sekarang pakai effective_last =
-- greatest(last_message_at, max(private_messages.created_at)).
-- ============================================================

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
      greatest(
        c.last_message_at,
        (select max(m.created_at) from private_messages m where m.chat_id = c.chat_id)
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
