-- ChatYuk: admin menandai chat dummy sudah dibaca dari monitor admin.
-- mark_chat_read biasa memakai SECURITY INVOKER + RLS participants, sehingga
-- dipanggil dari akun admin (bukan participant) tidak mengubah apa-apa.
-- RPC ini SECURITY DEFINER + guard admin (email zunixe@gmail.com / service_role).
-- ============================================================

create or replace function public.admin_mark_chat_read(p_chat_id text, p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  update public.private_chats
  set unread_counts = jsonb_set(coalesce(unread_counts, '{}'::jsonb), array[p_uid::text], '0'::jsonb),
      last_read_at = jsonb_set(coalesce(last_read_at, '{}'::jsonb), array[p_uid::text], to_jsonb(now()::text))
  where chat_id = p_chat_id;
end;
$$;

revoke execute on function public.admin_mark_chat_read(text, uuid) from public, anon;
grant execute on function public.admin_mark_chat_read(text, uuid) to authenticated, service_role;
