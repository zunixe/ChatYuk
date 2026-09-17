-- menyentuh: handle_new_private_message
-- List Pesan butuh centang-2 akurat: heuristic lastReadAt gagal karena
-- markAsRead saat buka chat memajukan myRead melewati pesan sendiri,
-- sehingga pengirim pesan terakhir tak bisa ditebak. Kolom baru
-- last_sender_id mencatat pengirim pesan terakhir per chat.

alter table public.private_chats
  add column if not exists last_sender_id uuid;

-- Backfill dari pesan terakhir per chat (pakai index chat_created).
update public.private_chats pc
set last_sender_id = m.sender_id
from (
  select distinct on (chat_id) chat_id, sender_id
  from public.private_messages
  order by chat_id, created_at desc, id desc
) m
where pc.chat_id = m.chat_id
  and pc.last_sender_id is null;

-- Trigger terbaru (dari supabase/snapshots/functions.sql @ 20260814250000)
-- + set last_sender_id = new.sender_id. Semua cabang preview dipertahankan
-- (image/view_once/coin/gift) + unread_counts + last_read_at.
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
    last_message = case
      when new.type = 'image' then '[Foto]'
      when new.type = 'view_once' then '[Foto]'
      when new.type = 'coin' then '[Koin]'
      when new.type = 'gift' then '[Hadiah]'
      else new.text end,
    last_message_at = now(),
    last_sender_id = new.sender_id,
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $$ language plpgsql security definer;
