-- ============================================================
-- Grup ala WA — Fase 2: invite langsung + promote admin.
--
-- 1) invite_to_room(p_room_id, p_uid): owner/admin menambah member
--    LANGSUNG (tanpa approval — owner yang menjamin). Hormati max_members.
--    Hapus status kicked lama bila ada (re-invite = maaf diterima).
--    Target boleh siapa pun yang pernah chat (cek di client dari daftar
--    chat); teman/bukan tidak dibedakan.
-- 2) set_member_role(p_room_id, p_uid, p_role): owner & admin bisa
--    angkat member→admin; demote admin→member & kick admin HANYA owner
--    (selaras kick_room_member). Client sudah memanggil RPC ini
--    (sebelumnya tidak ada → promote rusak).
-- ============================================================

-- 1) Invite langsung oleh owner/admin.
create or replace function public.invite_to_room(
  p_room_id text,
  p_uid uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  my_role text;
  r record;
  member_count int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_uid is null or p_uid = me then raise exception 'Invalid target'; end if;

  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if not r.is_private then raise exception 'Bukan grup private'; end if;
  if r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;

  my_role := public.fn_room_role(me, p_room_id);
  if my_role not in ('owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  if not exists (select 1 from public.profiles where id = p_uid) then
    raise exception 'User not found';
  end if;

  select count(*) into member_count
    from public.room_members where room_id = p_room_id;
  if member_count >= coalesce(r.max_members, 20)
     and not exists (
       select 1 from public.room_members
       where room_id = p_room_id and user_id = p_uid
     ) then
    raise exception 'Room full';
  end if;

  insert into public.room_members (room_id, user_id, role)
  values (p_room_id, p_uid, 'member')
  on conflict (room_id, user_id) do nothing;

  -- Bersihkan status kicked lama (re-invite = pintu dibuka lagi).
  delete from public.room_join_requests
   where room_id = p_room_id and user_id = p_uid;

  return jsonb_build_object('ok', true);
end;
$fn$;

revoke execute on function public.invite_to_room(text, uuid) from public, anon;
grant execute on function public.invite_to_room(text, uuid) to authenticated;

drop function if exists public.set_member_role(text, uuid, text);

-- 2) Set role member (promote/demote). Owner & admin bisa angkat
--    member→admin; HANYA owner boleh demote admin / menyentuh owner.
create or replace function public.set_member_role(
  p_room_id text,
  p_uid uuid,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  my_role text;
  target_role text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_uid is null or p_uid = me then raise exception 'Invalid target'; end if;
  if p_role not in ('admin', 'member') then raise exception 'Invalid role'; end if;
  if not exists (select 1 from public.rooms where id = p_room_id and is_private) then
    raise exception 'Room not found';
  end if;

  my_role := public.fn_room_role(me, p_room_id);
  if my_role not in ('owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  select role into target_role from public.room_members
   where room_id = p_room_id and user_id = p_uid;
  if target_role is null then raise exception 'Not a member'; end if;
  if target_role = 'owner' then raise exception 'Forbidden'; end if;
  -- Demote admin → member hanya owner (selaras kick_room_member).
  if target_role = 'admin' and my_role <> 'owner' then
    raise exception 'Forbidden';
  end if;

  update public.room_members set role = p_role
   where room_id = p_room_id and user_id = p_uid;
  return jsonb_build_object('ok', true, 'role', p_role);
end;
$fn$;

revoke execute on function public.set_member_role(text, uuid, text) from public, anon;
grant execute on function public.set_member_role(text, uuid, text) to authenticated;
