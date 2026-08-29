-- Fitur sematkan chat → pinned di urutan paling atas per-user
alter table public.private_chats
  add column if not exists pinned_by text[] not null default '{}',
  add column if not exists pinned_at jsonb not null default '{}'::jsonb;

create index if not exists idx_private_chats_pinned_by on public.private_chats using gin (pinned_by);

-- RPC pin/unpin (security definer, check participants — participants bisa uuid[] atau text[])
create or replace function public.pin_private_chat(p_chat_id text, p_pin boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  me uuid := auth.uid();
  me_text text := me::text;
  r record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into r from public.private_chats where chat_id = p_chat_id;
  if not found then raise exception 'Chat not found'; end if;
  if not exists (select 1 from unnest(r.participants::text[]) as p where p = me_text) then
    raise exception 'Forbidden';
  end if;

  if p_pin then
    update public.private_chats
    set pinned_by = array(select distinct unnest(array_append(coalesce(pinned_by,'{}'), me_text))),
        pinned_at = coalesce(pinned_at,'{}'::jsonb) || jsonb_build_object(me_text, now()::text)
    where chat_id = p_chat_id;
  else
    update public.private_chats
    set pinned_by = array_remove(coalesce(pinned_by,'{}'), me_text),
        pinned_at = coalesce(pinned_at,'{}'::jsonb) - me_text
    where chat_id = p_chat_id;
  end if;
  return jsonb_build_object('ok', true, 'pinned', p_pin);
end; $$;

revoke execute on function public.pin_private_chat(text, boolean) from public, anon;
grant execute on function public.pin_private_chat(text, boolean) to authenticated;
