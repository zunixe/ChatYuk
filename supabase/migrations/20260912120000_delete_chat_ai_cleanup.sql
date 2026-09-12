-- admin_delete_chat: selain hapus chat, hapus juga data AI milik dummy
-- peserta chat tsb (memory, claims, chat-state, pause). Chat manusia biasa
-- tidak punya baris di tabel-tabel itu → no-op.
-- (Body disalin dari versi live + tambahan block AI cleanup.)
create or replace function public.admin_delete_chat(p_chat_id text, p_delete_user_ids uuid[] DEFAULT '{}'::uuid[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  admin_email text := coalesce(auth.email(),'');
  photo_paths jsonb := '[]'::jsonb;
  v_uid uuid;
  v_parts uuid[];
begin
  if admin_email != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select participants into v_parts
  from public.private_chats where chat_id = p_chat_id;

  select coalesce(jsonb_agg(image_data), '[]'::jsonb) into photo_paths
  from private_messages
  where chat_id = p_chat_id
    and image_data like 'chat/%';

  delete from public.private_messages where chat_id = p_chat_id;
  delete from public.private_chats where chat_id = p_chat_id;

  -- AI cleanup utk dummy peserta chat ini (manusia biasa: no-op).
  if v_parts is not null then
    delete from public.ai_memory where dummy_uid = any (v_parts);
    delete from public.ai_reply_claims where dummy_uid = any (v_parts);
  end if;
  delete from public.ai_chat_state where chat_id = p_chat_id;
  delete from public.chat_ai_pause where chat_id = p_chat_id;

  if array_length(p_delete_user_ids, 1) is not null then
    set local session_replication_role = 'replica';

    foreach v_uid in array p_delete_user_ids loop
      if exists (
        select 1 from auth.users where id = v_uid and email = 'zunixe@gmail.com'
      ) then
        continue;
      end if;
      perform public.fn_archive_deleted_user(v_uid, 'admin_delete');
      delete from public.ai_memory where dummy_uid = v_uid or user_id = v_uid;
      delete from public.ai_chat_state where chat_id in (
        select chat_id from public.private_chats where v_uid = any (participants)
      );
      delete from public.room_presence where user_id = v_uid;
      delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
      delete from public.reports where reporter_id = v_uid or reported_id = v_uid;
      delete from public.user_photos where user_id = v_uid;
      delete from public.private_chats where v_uid = any (participants);
      delete from public.private_messages where sender_id = v_uid;
      delete from public.coin_ledger where user_id = v_uid;
      delete from public.point_events where user_id = v_uid;
      delete from public.topup_orders where user_id = v_uid;
      delete from public.dummy_accounts where uid = v_uid;
      delete from public.profiles where id = v_uid;
      delete from auth.users where id = v_uid;
    end loop;

    set local session_replication_role = 'origin';
  end if;

  return jsonb_build_object('ok', true, 'photo_paths', photo_paths);
end;
$function$;
