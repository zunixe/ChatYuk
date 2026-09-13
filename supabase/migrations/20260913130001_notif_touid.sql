-- ============================================================
-- Anti-bocor notifikasi multi-akun (admin ⇄ dummy satu HP).
--
-- Akar masalah: token FCM per-perangkat tersimpan di profil ADMIN dan
-- profil DUMMY sekaligus (satu HP dipakai swap sesi). Push untuk dummy
-- tetap sampai ke HP walau sesi aktif sudah kembali ke admin.
--
-- Fix lapis server: setiap payload push membawa 'toUid' = penerima.
-- Client (foreground + background isolate) membuang push yang toUid-nya
-- bukan sesi aktif. Dipakai bersama hygiene token client (clear+rotate
-- saat swap di DummySession).
-- ============================================================

-- 1) notify_private_message: chat + missed_call (basis 20260910000002).
create or replace function public.notify_private_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
  sender_avatar text;
  v_body text;
begin
  begin
    if new.type = 'call' then
      if exists (
        select 1 from public.private_messages
        where chat_id = new.chat_id
          and type = 'call'
          and created_at > now() - interval '30 seconds'
          and id <> new.id
      ) then
        return new;
      end if;
      select p into receiver_id from (
        select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
      ) x where x.p <> new.sender_id limit 1;
      if receiver_id is null then return new; end if;
      select fcm_token into receiver_token from public.profiles where id = receiver_id;
      if receiver_token is null or receiver_token = '' then return new; end if;
      select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
      sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', receiver_token,
          'title', sender_display,
          'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
          'data', jsonb_build_object(
            'type', 'missed_call',
            'toUid', receiver_id,
            'chatId', new.chat_id,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'callText', coalesce(new.text, 'Missed call'),
            'avatarUrl', coalesce(sender_avatar,''),
            'message', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
            'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab')
          )
        )
      );
      return new;
    end if;

    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is null then return new; end if;
    select fcm_token into receiver_token from public.profiles where id = receiver_id;
    if receiver_token is null or receiver_token = '' then return new; end if;
    select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
    sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
    -- Preview isi: teks (200 char) atau label tipe non-teks.
    v_body := case when new.type in ('image','view_once') then '[Foto]'
                   when new.type = 'voice' then '[Pesan suara]'
                   when new.type = 'coin' then '[Koin]'
                   when new.type = 'gift' then '[Hadiah]'
                   else left(coalesce(new.text,''), 200) end;
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
      body := jsonb_build_object(
        'token', receiver_token,
        'title', sender_display,
        'body', v_body,
        'data', jsonb_build_object(
          'type', 'message',
          'toUid', receiver_id,
          'chatId', new.chat_id,
          'otherUid', new.sender_id,
          'otherName', sender_display,
          'avatarUrl', coalesce(sender_avatar,''),
          'message', v_body,
          'body', v_body
        )
      )
    );
  exception when others then null;
  end;
  return new;
end; $$;

-- 2) call_push: panggilan masuk (basis 20260828010000).
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text, p_avatar text default ''
) returns void language plpgsql security definer set search_path = public as $$
declare
  t text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
  v_chat_id text;
  v_msg text;
begin
  select fcm_token into t from public.profiles where id = p_callee;
  if t is not null and t <> '' then
    v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
    v_msg := case when p_call_type = 'video' then 'Panggilan video' else 'Panggilan suara' end;
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
      body := jsonb_build_object(
        'token', t,
        'title', p_name,
        'body', v_msg,
        'data', jsonb_build_object(
          'type', 'call',
          'toUid', p_callee,
          'callId', p_call,
          'callerUid', p_caller,
          'fromName', p_name,
          'otherName', p_name,
          'callType', p_call_type,
          'chatId', v_chat_id,
          'avatarUrl', coalesce(p_avatar,''),
          'message', v_msg
        )
      )
    );
  end if;
end; $$;

-- 3) notify_call_ended: akhir panggilan (basis 20260828030000).
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
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', rec.fcm_token,
          'title', v_name,
          'body', v_body,
          'data', jsonb_build_object(
            'type', 'call_ended',
            'toUid', new.callee_id,
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
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'title', v_name,
            'body', v_body,
            'data', jsonb_build_object(
              'type', 'call_ended',
              'toUid', new.callee_id,
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

-- 4) social_push: follow/friend_request/subscribe (basis 20260827040000).
-- p_data pemanggil disatukan dengan toUid (tidak merusak shape lama).
create or replace function public.social_push(p_to uuid, p_title text, p_body text, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare rec record;
  sent boolean := false;
begin
  -- kirim ke semua device aktif yang punya token
  for rec in
    select fcm_token from public.user_devices
    where user_id = p_to and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object('token', rec.fcm_token, 'title', p_title, 'body', p_body, 'data', (coalesce(p_data, '{}'::jsonb) || jsonb_build_object('toUid', p_to)))
      );
    exception when others then null;
    end;
  end loop;

  -- fallback: jika belum ada baris device dengan token (klien lama), pakai profiles.fcm_token
  if not sent then
    declare t text;
    begin
      select fcm_token into t from public.profiles where id = p_to;
      if t is not null and t <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object('token', t, 'title', p_title, 'body', p_body, 'data', (coalesce(p_data, '{}'::jsonb) || jsonb_build_object('toUid', p_to)))
        );
      end if;
    exception when others then null;
    end;
  end if;
end;
$$;
