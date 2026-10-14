-- Sticker storage RLS: izinkan upload ke prefix `stickers/<uid>/...`.
--
-- Tanpa ini upload stiker gagal 403 (new row violates RLS) di bucket
-- chat-photos — terukur dari device. Aditif: sisip blok `stickers` ke
-- storage_object_owner_ok, sisanya dipertahankan.

create or replace function public.storage_object_owner_ok(p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'storage'
AS $function$
declare
  v_uid     text := auth.uid()::text;
  v_parts   text[] := storage.foldername(p_name);
  v_prefix  text := coalesce(v_parts[1], '');
  v_seg     text := coalesce(v_parts[2], '');
  v_base    text;
  v_stem    text;
  v_room    text;
begin
  if public.is_admin_request() then
    return true;
  end if;

  if coalesce(v_uid, '') = '' then
    return false;
  end if;

  v_base := coalesce(nullif(split_part(p_name, '/',
              array_length(string_to_array(p_name, '/'), 1)), ''), '');
  v_stem := split_part(v_base, '.', 1);

  -- avatars/<uid>_<ts>.jpg atau avatars/<uid>.jpg
  if v_prefix = 'avatars' then
    return (
      v_stem = v_uid
      or v_stem like v_uid || '\_%'
    );
  end if;

  -- gallery|posts|story|timeline/<uid>/<file>
  if v_prefix in ('gallery', 'posts', 'story', 'timeline') then
    return v_seg = v_uid;
  end if;

  -- room-icons/<uid>/<file>
  if v_prefix = 'room-icons' then
    return v_seg = v_uid;
  end if;

  -- stickers/<uid>/<file>  (stiker; owner-only)
  if v_prefix = 'stickers' then
    return v_seg = v_uid;
  end if;

  -- chat|voice/<chatId>/<file>
  if v_prefix in ('chat', 'voice') then
    -- (a) chat private → peserta.
    if exists (
      select 1 from public.private_chats pc
      where pc.chat_id = v_seg
        and auth.uid() = any (pc.participants)
    ) then
      return true;
    end if;
    -- (b) ROOM: segmen 'room_<roomId>' (foto/voice yang diunggah ke room).
    if v_seg like 'room\_%' then
      v_room := substr(v_seg, 6);   -- buang 'room_'
      -- Global room (publik) → siapa pun (terautentikasi) boleh posting.
      if exists (
        select 1 from public.rooms r
        where r.id = v_room and r.is_private = false
      ) then
        return true;
      end if;
      -- Grup private → harus anggota.
      return exists (
        select 1 from public.room_members m
        where m.room_id = v_room and m.user_id = auth.uid()
      );
    end if;
    return false;
  end if;

  -- prefix tidak dikenal → tolak (fail-closed)
  return false;
end;
$function$

