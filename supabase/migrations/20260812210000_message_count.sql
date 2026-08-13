-- ============================================================
-- ChatYuk: message_count di private_chats + filter chat kosong
-- - Tambah kolom message_count (badge jumlah pesan di list chat)
-- - Backfill dari pesan yang sudah ada
-- - Trigger increment message_count setiap pesan baru
-- Chat kosong (message_count = 0 / last_message = '') disembunyikan
-- dari list private chat di client.
-- ============================================================

alter table public.private_chats
  add column if not exists message_count integer not null default 0;

update public.private_chats pc
set message_count = (select count(*) from public.private_messages m where m.chat_id = pc.chat_id);

create or replace function public.handle_new_private_message() returns trigger as $$
declare
  receiver uuid;
  unread jsonb := '{}'::jsonb;
  lastread jsonb := '{}'::jsonb;
begin
  select p2 into receiver from (
    select unnest(participants) as p2 from public.private_chats where chat_id = new.chat_id
  ) x where p2 <> new.sender_id limit 1;
  if receiver is null then return new; end if;

  select coalesce(unread_counts, '{}'::jsonb) into unread from public.private_chats where chat_id = new.chat_id;
  if unread is null then unread := '{}'::jsonb; end if;
  unread := jsonb_set(unread, array[receiver::text], to_jsonb(coalesce((unread->>receiver::text)::int, 0) + 1), true);

  select coalesce(last_read_at, '{}'::jsonb) into lastread from public.private_chats where chat_id = new.chat_id;
  if lastread is null then lastread := '{}'::jsonb; end if;

  update public.private_chats set
    last_message = case when new.type = 'image' then '[Foto]' else new.text end,
    last_message_at = now(),
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $$ language plpgsql security definer;
