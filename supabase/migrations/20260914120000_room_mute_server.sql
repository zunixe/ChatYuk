-- menyentuh: (tidak ada fungsi frozen)
-- C1: samakan model mute room dengan private chat — SERVER sebagai sumber
-- kebenaran, bukan hanya SharedPreferences lokal (dulu mute room hilang saat
-- reinstall / tidak sinkron antar device).
--
-- Pola identik dengan 20260909000000_mute_archive_chats.sql (private_chats):
--   - kolom rooms.muted_by text[] (daftar uid yang membisukan room)
--   - RPC mute_room(room_id, mute) security definer + cek keanggotaan
--
-- Backward-compat: kode tetap menulis prefs lokal (offline-first) + server.
alter table public.rooms
  add column if not exists muted_by text[] not null default '{}';

create index if not exists idx_rooms_muted_by on public.rooms using gin (muted_by);

create or replace function public.mute_room(p_room_id text, p_mute boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  me uuid := auth.uid();
  me_text text := me::text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'Room not found';
  end if;
  if p_mute then
    update public.rooms
    set muted_by = array(select distinct unnest(array_append(coalesce(muted_by,'{}'), me_text)))
    where id = p_room_id;
  else
    update public.rooms
    set muted_by = array_remove(coalesce(muted_by,'{}'), me_text)
    where id = p_room_id;
  end if;
  return jsonb_build_object('ok', true, 'muted', p_mute);
end; $$;

revoke execute on function public.mute_room(text, boolean) from public, anon;
grant execute on function public.mute_room(text, boolean) to authenticated;
