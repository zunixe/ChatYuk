-- Trigger: kirim FCM push ke penerima saat ada panggilan masuk.
-- Supaya call tetap masuk walau aplikasi penerima force-stop / tertutup total.
-- Jalankan sekali di Supabase SQL Editor.

create or replace function public.notify_call() returns trigger as $$
declare
  receiver_token text;
  caller_name text;
  v_chat_id text;
begin
  -- Hanya kirim untuk status awal ringing (hindari dobel saat update).
  if new.status <> 'ringing' then
    return new;
  end if;

  select fcm_token into receiver_token
    from public.profiles where id = new.callee_id;
  select nickname into caller_name
    from public.profiles where id = new.caller_id;

  if receiver_token is null or receiver_token = '' then
    return new;
  end if;

  -- Format chat_id sama dengan client: uid disort lalu digabung '_'.
  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' ||
               greatest(new.caller_id::text, new.callee_id::text);

  begin
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', receiver_token,
        'data', jsonb_build_object(
          'type', 'call',
          'callId', new.id,
          'callerUid', new.caller_id,
          'callType', coalesce(new.call_type, 'video'),
          'chatId', v_chat_id,
          'otherName', coalesce(caller_name, 'User'),
          'fromName', coalesce(caller_name, 'User')
        )
      )
    );
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

drop trigger if exists calls_notify_trigger on public.calls;
create trigger calls_notify_trigger
  after insert on public.calls
  for each row execute function public.notify_call();
