-- ============================================================
-- FCM per-device: simpan token di user_devices, fan-out push ke semua
-- device aktif. Uninstall = token lama NotRegistered, install baru
-- dapat token baru dan baris device baru (install_id beda) atau update.
-- ============================================================

-- 1. kolom token per device (kosong = belum pernah sync)
alter table public.user_devices
  add column if not exists fcm_token text not null default '';

create index if not exists user_devices_fcm_idx
  on public.user_devices (user_id) where fcm_token <> '';

-- 2. helper: simpan token untuk device yang sedang login
create or replace function public.update_device_fcm_token(
  p_install_id text, p_token text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_install_id is null or p_install_id = '' then
    return;
  end if;

  -- upsert minimal baris device jika belum ada (mis. token datang sebelum upsert_device)
  insert into public.user_devices (user_id, install_id, fcm_token, last_seen_at, is_active)
    values (uid, p_install_id, coalesce(p_token,''), now(), true)
  on conflict (user_id, install_id)
  do update set fcm_token = excluded.fcm_token, last_seen_at = now(), is_active = true;

  -- sync juga ke profiles untuk kompatibilitas client lama yang masih baca profiles.fcm_token
  update public.profiles set fcm_token = coalesce(p_token,'') where id = uid;
end;
$$;

revoke execute on function public.update_device_fcm_token(text,text) from public, anon;
grant execute on function public.update_device_fcm_token(text,text) to authenticated;

-- 3. fan-out helper: ganti social_push single-token jadi multi-device
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
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('token', rec.fcm_token, 'title', p_title, 'body', p_body, 'data', p_data)
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
          headers := jsonb_build_object('Content-Type', 'application/json'),
          body := jsonb_build_object('token', t, 'title', p_title, 'body', p_body, 'data', p_data)
        );
      end if;
    exception when others then null;
    end;
  end if;
end;
$$;

-- 4. call_push juga fan-out (dipanggil trigger ringing)
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
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  for rec in
    select fcm_token from public.user_devices
    where user_id = p_callee and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'token', rec.fcm_token,
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
    exception when others then null;
    end;
  end if;
end;
$$;

-- 5. notify_call_ended juga fan-out
create or replace function public.notify_call_ended() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  v_chat_id text;
  sent boolean := false;
begin
  if old.status <> 'ringing' then return new; end if;
  if new.status not in ('canceled','missed','declined','ended','busy') then return new; end if;
  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' || greatest(new.caller_id::text, new.callee_id::text);
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
          'data', jsonb_build_object('type','call_canceled','callId', new.id, 'chatId', v_chat_id)
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
          body := jsonb_build_object('token', t, 'data', jsonb_build_object('type','call_canceled','callId', new.id, 'chatId', v_chat_id))
        );
      end if;
    exception when others then null;
    end;
  end if;
  return new;
exception when others then return new;
end;
$$;
