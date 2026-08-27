-- ============================================================
-- ChatYuk: Perbaikan notifikasi call (nama) + missed call +
-- skip pesan riwayat call + batalkan notif call saat berakhir.
-- ============================================================

-- 1) call_push: tambah 'otherName' (alias fromName) supaya handler client
--    selalu menemukan nama caller, baik via fromName maupun otherName.
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text
) returns void language plpgsql security definer set search_path = public as $$
declare
  t text;
  v_chat_id text;
begin
  select fcm_token into t from public.profiles where id = p_callee;
  if t is not null and t <> '' then
    v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', t,
        'title', p_caller_name,
        'body', p_call_type,
        'data', jsonb_build_object(
          'type', 'call',
          'callId', p_call,
          'callerUid', p_caller,
          'fromName', p_caller_name,
          'otherName', p_caller_name,
          'callType', p_call_type,
          'chatId', v_chat_id
        )
      )
    );
  end if;
end; $$;

-- 2) Trigger pesan private: JANGAN push untuk pesan riwayat call
--    (type='call') — panggilan punya notifikasinya sendiri (calls trigger).
--    Ini mencegah "pesan baru masuk" muncul saat miscall.
create or replace function public.notify_private_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
begin
  begin
    if new.type = 'call' then
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
      headers := jsonb_build_object('Content-Type', 'application/json'),
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

-- 3) Trigger batalkan notifikasi call saat panggilan berakhir sebelum dijawab.
--    Client menerima type='call_canceled' lalu membatalkan notifikasi panggilan
--    yang masih nyangkut ("video call" padahal sudah diputus).
create or replace function public.notify_call_ended() returns trigger as $$
declare
  receiver_token text;
  v_chat_id text;
begin
  begin
    if old.status <> 'ringing' then
      return new;
    end if;
    if new.status not in ('canceled','missed','declined','ended','busy') then
      return new;
    end if;
    select fcm_token into receiver_token from public.profiles where id = new.callee_id;
    if receiver_token is null or receiver_token = '' then
      return new;
    end if;
    v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' || greatest(new.caller_id::text, new.callee_id::text);
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', receiver_token,
        'data', jsonb_build_object(
          'type', 'call_canceled',
          'callId', new.id,
          'chatId', v_chat_id
        )
      )
    );
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

drop trigger if exists calls_notify_ended_trigger on public.calls;
create trigger calls_notify_ended_trigger
  after update on public.calls
  for each row execute function public.notify_call_ended();
