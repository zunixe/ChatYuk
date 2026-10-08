-- ============================================================
-- Admin: hapus room APA PUN (termasuk room tanpa owner / global room).
--
-- LATAR: `delete_private_room` mengizinkan OWNER room atau ADMIN, tapi
-- untuk room yang TIDAK punya owner (mayoritas global room: owner_id null)
-- cek `r.owner_id <> uid` bernilai true → admin pun ditolak lewat RPC itu.
-- Panel admin perlu bisa membersihkan room kotor/spam tanpa syarat owner.
--
-- RPC `admin_delete_room`: hanya admin (email zunixe@gmail.com), hapus room
-- apa pun. FK cascade menghapus messages/room_members/room_presence.
--
-- Tidak menyentuh fungsi FROZEN.
-- ============================================================

create or replace function public.admin_delete_room(p_room_id text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  admin_email text := coalesce(auth.email(), '');
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if admin_email <> 'zunixe@gmail.com' then raise exception 'Not admin'; end if;

  -- Idempoten: kalau sudah tidak ada, tidak error.
  delete from public.rooms where id = p_room_id;
end;
$function$;

revoke execute on function public.admin_delete_room(text) from public, anon;
grant execute on function public.admin_delete_room(text) to authenticated, service_role;
