-- Tambah kolom reply quote di private_messages (dipakai RPC admin_get_chat_messages
-- dan insert chat_service.sendPrivateMessage saat reply). Idempotent.
alter table public.private_messages
  add column if not exists replied_to_id bigint;

alter table public.private_messages
  add column if not exists replied_to_text text;

alter table public.private_messages
  add column if not exists replied_to_sender_name text;
