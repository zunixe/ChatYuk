-- ============================================================
-- ChatYuk: Perbaikan notifikasi push (call + pesan masuk Android)
-- Akar masalah: token FCM mati (NotRegistered) + trigger call dobel
-- + trigger pesan tanpa field 'type' + Android 13 permission/channel.
-- ============================================================

-- 1) Hapus trigger call DOBEL: `calls_notify_trigger` (dari
--    notify_call_trigger.sql) redundan dengan `notify_call_ringing_trigger`
--    (dari calls.sql). Sisakan SATU agar tidak dobel push per call.
drop trigger if exists calls_notify_trigger on public.calls;
drop function if exists public.notify_call();

-- 2) Perbaiki trigger pesan private: tambah 'type' di data + gunakan
--    notification block supaya muncul saat app TERMINATED (bukan data-only).
--    Title = nama pengirim dari profiles, body = preview pesan.
create or replace function public.notify_private_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
begin
  begin
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

-- 3) Hapus token FCM mati/NotRegistered semua user. Client akan mengisi ulang
--    token segar saat login/register berikutnya (updateFcmToken di bootstrap).
update public.profiles set fcm_token = '' where fcm_token is not null and fcm_token <> '';