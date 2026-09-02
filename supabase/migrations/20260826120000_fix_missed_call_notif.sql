-- ============================================================
-- Fix: missed call / call history notification
-- - Sebelumnya type='call' di private_messages di-return tanpa push,
--   sehingga tidak ada notif sama sekali untuk missed call.
-- - Sekarang kirim push terpisah type='missed_call' dengan
--   title=nama penelpon, body=status call (Missed call / Call ended)
-- - Pesan text biasa (type != 'call') tetap seperti semula
-- ============================================================

create or replace function public.notify_private_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
begin
  begin
    -- JANGAN push untuk pesan call history sebagai "pesan baru",
    -- tapi kirim push khusus missed_call agar ada notif sendiri
    if new.type = 'call' then
      select p into receiver_id from (
        select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
      ) x where x.p <> new.sender_id limit 1;
      if receiver_id is null then
        return new;
      end if;
      select fcm_token into receiver_token from public.profiles where id = receiver_id;
      if receiver_token is null or receiver_token = '' then
        return new;
      end if;
      select nickname into sender_display from public.profiles where id = new.sender_id;
      sender_display := coalesce(sender_display, new.sender_name, 'User');
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', receiver_token,
          'title', sender_display,
          'body', new.text,
          'data', jsonb_build_object(
            'type', 'missed_call',
            'chatId', new.chat_id,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'callText', new.text
          )
        )
      );
      return new;
    end if;

    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is null then
      return new;
    end if;
    select fcm_token into receiver_token from public.profiles where id = receiver_id;
    if receiver_token is null or receiver_token = '' then
      return new;
    end if;
    select nickname into sender_display from public.profiles where id = new.sender_id;
    sender_display := coalesce(sender_display, new.sender_name, 'User');
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
      body := jsonb_build_object(
        'token', receiver_token,
        'title', sender_display,
        'body', case when new.type in ('image','view_once') then '[Foto]'
                     when new.type = 'coin' then '[Koin]'
                     when new.type = 'gift' then '[Hadiah]'
                     else left(new.text, 200) end,
        'data', jsonb_build_object(
          'type', 'message',
          'chatId', new.chat_id,
          'otherUid', new.sender_id,
          'otherName', sender_display
        )
      )
    );
  exception when others then
    null;
  end;
  return new;
end; $$;
