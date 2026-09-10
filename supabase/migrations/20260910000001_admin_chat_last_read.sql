-- ChatYuk: monitor admin butuh last_read_at per chat untuk samakan
-- centang-2 dengan chat asli (sebelumnya isRead:isMe hardcoded di client
-- sehingga semua bubble kanan selalu centang-2).
-- READ-ONLY (tidak mengubah apa pun); guard sama dengan RPC monitor lain.
-- ============================================================

create or replace function public.admin_get_chat_last_read(p_chat_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(last_read_at, '{}'::jsonb) into result
  from public.private_chats
  where chat_id = p_chat_id;

  return coalesce(result, '{}'::jsonb);
end;
$function$;

revoke execute on function public.admin_get_chat_last_read(text) from public, anon;
grant execute on function public.admin_get_chat_last_read(text) to authenticated, service_role;
