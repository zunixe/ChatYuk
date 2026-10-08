-- ============================================================
-- ChatYuk: Kontak admin — tampilkan nickname + avatar pengirim.
--
-- Masalah: `admin_contact_messages_page` hanya mengembalikan `name` (dari
-- form, bisa null) + `user_id`. UI admin tak bisa menampilkan username &
-- avatar pengirim → pesan tampil tanpa identitas (name `—`).
--
-- Fix: JOIN ke `profiles` by user_id → kembalikan `nickname` + `avatar`
-- (avatar = path storage atau base64; UI `ProfileAvatar(uid)` resolve sendiri
-- via AvatarB64Service, jadi nickname cukup untuk label).
--
-- `user_id` bisa null (pengirim anonim / tanpa sesi) → LEFT JOIN.
-- ============================================================

create or replace function public.admin_contact_messages_page(
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.contact_messages),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'created_at', m.created_at,
        'name', m.name,
        'message', m.message,
        'user_id', m.user_id,
        'is_read', m.is_read,
        -- Identitas pengirim dari profil (bila login). nickname fallback ke
        -- 'Anon' (default kolom), avatar = path/base64 (UI resolve sendiri).
        'nickname', p.nickname,
        'avatar', p.avatar
      ) order by m.created_at desc
    ), '[]'::jsonb)
  )
  into result
  from (
    select * from public.contact_messages
    order by created_at desc
    limit p_limit offset p_offset
  ) m
  left join public.profiles p on p.id = m.user_id;

  return result;
end;
$$;

grant execute on function public.admin_contact_messages_page(integer, integer) to authenticated;
