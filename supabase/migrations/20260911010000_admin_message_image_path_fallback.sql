-- ChatYuk: foto chat baru menyimpan PATH di kolom image_path (image_data
-- kosong untuk hemat DB). RPC admin_get_message_image lama hanya
-- mengembalikan image_data → monitor admin selalu dapat string kosong →
-- "ketuk untuk memuat" tidak pernah memuat (kasus chat AntoSusanto).
-- Fix: fallback ke image_path bila image_data kosong — client sudah
-- mendukung respons berupa path (download otomatis dari bucket).
-- ============================================================

create or replace function public.admin_get_message_image(p_message_id bigint)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(nullif(m.image_data, ''), m.image_path) into result
  from private_messages m
  where m.id = p_message_id;

  return result;
end;
$function$;

revoke execute on function public.admin_get_message_image(bigint) from public, anon;
grant execute on function public.admin_get_message_image(bigint) to authenticated, service_role;
