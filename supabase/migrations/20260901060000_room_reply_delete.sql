-- Room chat: reply + hapus pesan sendiri (paritas dengan private chat)
alter table public.messages add column if not exists is_deleted bool not null default false;
alter table public.messages add column if not exists edited bool not null default false;
alter table public.messages add column if not exists replied_to_id bigint;
alter table public.messages add column if not exists replied_to_text text;
alter table public.messages add column if not exists replied_to_sender_name text;

-- Hanya pengirim boleh update pesannya (soft delete / edit)
drop policy if exists "messages_update_own" on public.messages;
create policy "messages_update_own" on public.messages for update
  to authenticated
  using (auth.uid() = sender_id)
  with check (auth.uid() = sender_id);
