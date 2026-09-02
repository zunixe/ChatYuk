-- Sinkron total DB ↔ code — fix bersimpangan yang bikin 3 notifikasi.
-- Masalah:
-- 1) call_push masih versi lama (profiles.fcm_token only) → ringing fan-out tidak konsisten
--    dengan notify_call_ended yang sudah fan-out via user_devices. Akibat token
--    bisa beda device, ringing tidak update.
-- 2) notify_call_ended sekarang kirim type='call_ended' data-only, tapi code
--    main.dart untuk call_ended hanya show update, tidak dismiss IncomingCallScreen
--    (dulu dismiss ada di call_canceled). Jadi IncomingCallScreen tertinggal + notif update + call_active = 3.
-- Fix: call_push fan-out + notify_call_ringing konsisten, notify_call_ended tetap
-- data-only tapi code akan handle dismiss (lihat lib/main.dart).

-- 1) call_push fan-out (sinkron dengan notify_call_ended 27100000)
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  sent boolean := false;
  v_chat_id text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  -- fan-out ke semua device aktif
  for rec in
    select fcm_token from public.user_devices
    where user_id = p_callee and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', rec.fcm_token,
          'title', p_name,
          'body', p_call_type,
          'data', jsonb_build_object(
            'type', 'call',
            'callId', p_call,
            'callerUid', p_caller,
            'fromName', p_name,
            'otherName', p_name,
            'callType', p_call_type,
            'chatId', v_chat_id
          )
        )
      );
    exception when others then null;
    end;
  end loop;

  if not sent then
    declare t text;
    begin
      select fcm_token into t from public.profiles where id = p_callee;
      if t is not null and t <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'title', p_name,
            'body', p_call_type,
            'data', jsonb_build_object(
              'type', 'call',
              'callId', p_call,
              'callerUid', p_caller,
              'fromName', p_name,
              'otherName', p_name,
              'callType', p_call_type,
              'chatId', v_chat_id
            )
          )
        );
      end if;
    exception when others then null;
    end;
  end if;
end;
$$;

-- 2) notify_call_ringing tetap pakai call_push yang baru (tidak perlu ubah, sudah panggil call_push)
--    Pastikan trigger tetap AFTER INSERT ringing only
drop trigger if exists notify_call_ringing_trigger on public.calls;
create trigger notify_call_ringing_trigger
  after insert on public.calls
  for each row execute function public.notify_call_ringing();

-- 3) Pastikan notify_call_ended versi 27100000 tetap (sudah data-only + body di data)
--    Tidak diubah di sini, hanya pastikan call_push konsisten
