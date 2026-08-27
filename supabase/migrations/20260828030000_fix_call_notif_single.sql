-- Fix: video call 3 notifikasi (2 canceled + 1 ended) → 1 saja
-- Penyebab: trigger lama `calls_notify_canceled_trigger` (dari 20260827040000)
-- masih ada bersama `calls_notify_ended_trigger`, sehingga status `canceled`
-- mengirim 2 push (1 per device fan-out × 2 trigger) + 1 ended.
-- Solusi: hapus semua trigger call lama, buat ulang hanya 2 yang benar,
-- dan pastikan call_ended hanya kirim sekali per call.

-- Hapus trigger lama yang mungkin masih ada
drop trigger if exists calls_notify_canceled_trigger on public.calls;
drop trigger if exists notify_call_canceled_trigger on public.calls;
drop trigger if exists calls_notify_trigger on public.calls;

-- Pastikan notify_call_ended hanya kirim sekali (idempoten via column)
alter table public.calls add column if not exists notif_sent_at timestamptz;

create or replace function public.notify_call_ended() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rec record;
  v_chat_id text;
  v_name text;
  v_body text;
  sent boolean := false;
begin
  -- Hanya transisi pertama dari ringing/answered ke terminal
  if old.status not in ('ringing','answered') then return new; end if;
  if new.status not in ('canceled','missed','declined','ended','busy') then return new; end if;
  -- Idempoten: jika sudah pernah kirim untuk call ini, jangan kirim lagi
  if new.notif_sent_at is not null then return new; end if;

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

  -- Tandai sudah dikirim supaya update berikutnya tidak kirim lagi
  new.notif_sent_at := now();
  return new;
exception when others then return new;
end; $$;

drop trigger if exists calls_notify_ended_trigger on public.calls;
create trigger calls_notify_ended_trigger
  before update on public.calls
  for each row execute function public.notify_call_ended();
