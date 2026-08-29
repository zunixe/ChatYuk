-- P0: ganti RLS private_messages select yang berat (per-row) dengan RPC security definer
-- Matikan RLS select (force RPC), client pakai get_chat_messages

drop policy if exists "private_messages_select" on public.private_messages;
create policy "private_messages_select" on public.private_messages for select using (false);

-- Tambah index untuk @> GIN sudah ada, tapi pastikan query pakai @>
create index if not exists idx_private_chats_participants_gin on public.private_chats using gin (participants);
create index if not exists idx_private_chats_last_message_at_brin on public.private_chats using brin (last_message_at);

-- RPC get_chat_messages
create or replace function public.get_chat_messages(p_chat_id text, p_before_id bigint default null, p_limit int default 50)
returns jsonb language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); ok bool;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select exists(select 1 from public.private_chats where chat_id=p_chat_id and participants @> array[me]) into ok;
  if not ok then raise exception 'Forbidden'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc),'[]'::jsonb)
          from (select * from public.private_messages where chat_id=p_chat_id and (p_before_id is null or id < p_before_id) order by created_at desc limit least(p_limit,100)) m);
end; $$;
grant execute on function public.get_chat_messages(text,bigint,int) to authenticated;

create or replace function public.get_room_messages(p_room_id text, p_before_id bigint default null, p_limit int default 50)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc),'[]'::jsonb)
          from (select * from public.messages where room_id=p_room_id and (p_before_id is null or id < p_before_id) order by created_at desc limit least(p_limit,100)) m);
end; $$;
grant execute on function public.get_room_messages(text,bigint,int) to authenticated;
