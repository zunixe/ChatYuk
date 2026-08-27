-- Unified avatar + message preview untuk semua notifikasi
-- call, message, missed_call — samakan payload shape

-- call_push: tambah avatarUrl + message preview
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
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', t,
        'title', p_name,
        'body', v_msg,
        'data', jsonb_build_object(
          'type', 'call',
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

create or replace function public.notify_call_ringing() returns trigger as $$
declare caller_name text; caller_avatar text;
begin
  if new.status <> 'ringing' then return new; end if;
  select nickname, avatar into caller_name, caller_avatar from public.profiles where id = new.caller_id;
  perform public.call_push(new.callee_id, new.id, new.caller_id, coalesce(nullif(caller_name,''), 'User'), new.call_type, coalesce(caller_avatar,''));
  return new;
exception when others then return new;
end; $$ language plpgsql security definer;

-- notify_private_message: tambah avatarUrl
create or replace function public.notify_private_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
  sender_avatar text;
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
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'token', receiver_token,
          'title', sender_display,
          'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
          'data', jsonb_build_object(
            'type', 'missed_call',
            'chatId', new.chat_id,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'callText', coalesce(new.text, 'Missed call'),
            'avatarUrl', coalesce(sender_avatar,''),
            'message', coalesce(nullif(new.text,''), 'Panggilan tak terjawab')
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
          'otherName', sender_display,
          'avatarUrl', coalesce(sender_avatar,''),
          'message', left(coalesce(new.text,''), 200)
        )
      )
    );
  exception when others then null;
  end;
  return new;
end; $$;
