-- ============================================================
-- ChatYuk: Notifikasi push saat contact online
-- Trigger profiles.status → 'online': kirim FCM push ke semua
-- user yang pernah private chat dengan user tsb.
-- Data-only (tanpa notification block) — teks dirender client
-- supaya bisa bilingual (Indonesia/English).
-- ============================================================

create or replace function public.notify_contact_online() returns trigger as $$
declare
  contact_id uuid;
  contact_token text;
  contact_chat text;
begin
  begin
    -- Hanya transisi ke 'online' (bukan update berulang saat sudah online)
    if new.status <> 'online' or old.status = 'online' then
      return new;
    end if;
    for contact_id, contact_chat in
      select distinct u as uid, pc.chat_id
      from public.private_chats pc
      cross join lateral unnest(pc.participants) as u
      where new.id = any (pc.participants)
        and u <> new.id
    loop
      select fcm_token into contact_token
      from public.profiles where id = contact_id;
      if contact_token is not null and contact_token <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', contact_token,
            'title', coalesce(new.name, 'Anon'),
            'body', 'is online',
            'data', jsonb_build_object(
              'type', 'online',
              'chatId', contact_chat,
              'otherUid', new.id,
              'otherName', coalesce(new.name, 'Anon')
            )
          )
        );
      end if;
    end loop;
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

drop trigger if exists notify_contact_online_trigger on public.profiles;
create trigger notify_contact_online_trigger
  after update of status on public.profiles
  for each row
  execute function public.notify_contact_online();