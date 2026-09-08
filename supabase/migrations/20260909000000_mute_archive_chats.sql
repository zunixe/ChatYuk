-- Fitur mute notifikasi & arsip chat per-user (gaya WhatsApp).
-- Cara pakai: jalankan file ini sekali di Supabase Dashboard → SQL Editor.
-- Tanpa migrasi ini, tombol Bisukan/Arsipkan di app akan gagal (kolom belum ada).

alter table public.private_chats
  add column if not exists muted_by text[] not null default '{}',
  add column if not exists archived_by text[] not null default '{}';

create index if not exists idx_private_chats_muted_by on public.private_chats using gin (muted_by);
create index if not exists idx_private_chats_archived_by on public.private_chats using gin (archived_by);

-- RPC mute/unmute (security definer, check participants — participants bisa uuid[] atau text[])
create or replace function public.mute_private_chat(p_chat_id text, p_mute boolean default true)
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

  if p_mute then
    update public.private_chats
    set muted_by = array(select distinct unnest(array_append(coalesce(muted_by,'{}'), me_text)))
    where chat_id = p_chat_id;
  else
    update public.private_chats
    set muted_by = array_remove(coalesce(muted_by,'{}'), me_text)
    where chat_id = p_chat_id;
  end if;
  return jsonb_build_object('ok', true, 'muted', p_mute);
end; $$;

revoke execute on function public.mute_private_chat(text, boolean) from public, anon;
grant execute on function public.mute_private_chat(text, boolean) to authenticated;

-- RPC archive/unarchive (pola sama)
create or replace function public.archive_private_chat(p_chat_id text, p_archive boolean default true)
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

  if p_archive then
    update public.private_chats
    set archived_by = array(select distinct unnest(array_append(coalesce(archived_by,'{}'), me_text)))
    where chat_id = p_chat_id;
  else
    update public.private_chats
    set archived_by = array_remove(coalesce(archived_by,'{}'), me_text)
    where chat_id = p_chat_id;
  end if;
  return jsonb_build_object('ok', true, 'archived', p_archive);
end; $$;

revoke execute on function public.archive_private_chat(text, boolean) from public, anon;
grant execute on function public.archive_private_chat(text, boolean) to authenticated;
