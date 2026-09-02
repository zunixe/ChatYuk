-- Fix 9→10: call_ended HARUS data-only (bug 3 notifikasi).
-- Sebelumnya call_ended dikirim sebagai notification block → FCM auto-tampilkan
-- 1 notif (id random) + Flutter background handler tampilkan 1 lagi (id=chatId)
-- = dobel, plus ringing asli = 3.
-- Sekarang: kirim body juga di dalam data['body'] agar Flutter bisa render
-- tanpa notification block (send-push dataOnlyTypes sudah include call_ended).

create or replace function public.notify_call_ended() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rec record;
  v_chat_id text;
  v_name text;
  v_body text;
  sent boolean := false;
begin
  if old.status <> 'ringing' and old.status <> 'answered' then return new; end if;
  if new.status not in ('canceled','missed','declined','ended','busy') then return new; end if;

  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' || greatest(new.caller_id::text, new.callee_id::text);

  select nickname into v_name from public.profiles where id = new.caller_id;
  v_name := coalesce(nullif(v_name,''), 'User');

  v_body := case
    when new.status in ('ended','canceled') then 'Call ended'
    when new.status = 'missed' then 'Missed call'
    when new.status = 'declined' then 'Call declined'
    when new.status = 'busy' then 'Busy'
    else 'Call ended'
  end;

  for rec in
    select fcm_token from public.user_devices
    where user_id = new.callee_id and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', rec.fcm_token,
          'title', v_name,
          'body', v_body,
          'data', jsonb_build_object(
            'type', 'call_ended',
            'callId', new.id,
            'chatId', v_chat_id,
            'callerUid', new.caller_id,
            'otherName', v_name,
            'body', v_body
          )
        )
      );
    exception when others then null;
    end;
  end loop;

  if not sent then
    declare t text;
    begin
      select fcm_token into t from public.profiles where id = new.callee_id;
      if t is not null and t <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'title', v_name,
            'body', v_body,
            'data', jsonb_build_object(
              'type', 'call_ended',
              'callId', new.id,
              'chatId', v_chat_id,
              'callerUid', new.caller_id,
              'otherName', v_name,
              'body', v_body
            )
          )
        );
      end if;
    exception when others then null;
    end;
  end if;
  return new;
exception when others then return new;
end; $$;
