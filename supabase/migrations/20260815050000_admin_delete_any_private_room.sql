-- ============================================================
-- ChatYuk: Admin boleh hapus private room manapun
-- - Owner tetap bisa hapus room-nya sendiri
-- - Admin (zunixe@gmail.com) bisa hapus room private siapa pun
-- ============================================================

create or replace function public.delete_private_room(p_room_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  admin_email text := coalesce(auth.email(), '');
  r record;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then return; end if;
  -- Owner ATAU admin boleh menghapus.
  if r.owner_id <> uid and admin_email <> 'zunixe@gmail.com' then
    raise exception 'Not owner';
  end if;
  -- messages, room_members, room_presence ikut terhapus via FK cascade
  delete from public.rooms where id = p_room_id;
end;
$$;

revoke execute on function public.delete_private_room(text) from public, anon;
grant execute on function public.delete_private_room(text) to authenticated;
