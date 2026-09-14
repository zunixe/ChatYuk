-- Fix: trigger check_private_chat_update menolak sync snapshot profil
-- ke chat dummy dengan user lain (admin bukan participant) → P0001 saat
-- edit profil dummy di admin. Bypass untuk admin via is_admin_request().
-- Participant biasa tetap terkunci; participants tetap tidak boleh diubah.
create or replace function public.check_private_chat_update()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Admin (email claim / DB email / service_role) boleh update apapun
  -- (dipakai sync_profile_to_chats dari admin_update_dummy_profile).
  if public.is_admin_request() then
    return new;
  end if;
  -- Hanya participant yang boleh update
  if not (auth.uid() = any (new.participants)) then
    raise exception 'Not authorized';
  end if;
  -- Participant tidak boleh diubah setelah dibuat
  if new.participants != old.participants then
    raise exception 'Cannot modify participants';
  end if;
  return new;
end;
$$;
