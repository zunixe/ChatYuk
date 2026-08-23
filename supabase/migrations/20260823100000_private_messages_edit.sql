-- Izinkan edit pesan sendiri di private chat (ubah teks + tandai edited).
alter table public.private_messages
  add column if not exists edited boolean not null default false;

drop policy if exists "private_messages_update" on public.private_messages;
create policy "private_messages_update" on public.private_messages
  for update
  using (
    auth.uid() = sender_id
    and exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
  )
  with check (auth.uid() = sender_id);
