-- ============================================================
-- Rombak total model notifikasi call → SATU notifikasi per call
-- dengan ID konsisten (chatId) yang isinya di-update, bukan tambah.
--
-- Alur:
--   1) ringing → push 'call' (data-only) → client tampilkan notif ringing
--   2) dibatalkan/diangkat-selesai → push 'call_ended' (notification block,
--      title=nama, body=status) → client UPDATE notif yang sama (id=chatId)
--
-- Dihilangkan: push missed_call & message dari pesan type='call' (sumber
-- notif ganda + kosong). call_canceled tidak dipakai lagi.
-- ============================================================

-- 1) Pesan riwayat call (type='call') TIDAK menembak push apa pun.
--    Notif call ditangani sendiri oleh notify_call_ringing + notify_call_ended.
create or replace function public.notify_private_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
begin
  begin
    if new.type = 'call' then
      return new; -- call history: tanpa notifikasi (dedicated call notif)
    end if;

    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is null then return new; end if;
    select fcm_token into receiver_token from public.profiles where id = receiver_id;
    if receiver_token is null or receiver_token = '' then return new; end if;
    select nickname into sender_display from public.profiles where id = new.sender_id;
    sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', receiver_token,
        'title', sender_display,
        'body', case when new.type in ('image','view_once') then '[Foto]'
                     when new.type = 'coin' then '[Koin]'
                     when new.type = 'gift' then '[Hadiah]'
                     else left(coalesce(new.text,''), 200) end,
        'data', jsonb_build_object(
          'type', 'message',
          'chatId', new.chat_id,
          'otherUid', new.sender_id,
          'otherName', sender_display
        )
      )
    );
  exception when others then null;
  end;
  return new;
end; $$;

-- 2) notify_call_ended → push 'call_ended' (notification block) fan-out per device.
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
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'token', rec.fcm_token,
          'title', v_name,
          'body', v_body,
          'data', jsonb_build_object(
            'type', 'call_ended',
            'callId', new.id,
            'chatId', v_chat_id,
            'callerUid', new.caller_id,
            'otherName', v_name
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
          headers := jsonb_build_object('Content-Type', 'application/json'),
          body := jsonb_build_object(
            'token', t,
            'title', v_name,
            'body', v_body,
            'data', jsonb_build_object(
              'type', 'call_ended',
              'callId', new.id,
              'chatId', v_chat_id,
              'callerUid', new.caller_id,
              'otherName', v_name
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

drop trigger if exists calls_notify_ended_trigger on public.calls;
create trigger calls_notify_ended_trigger
  after update on public.calls
  for each row execute function public.notify_call_ended();
