-- ============================================================
-- Langkah 1 (b): notif call/online/broadcast → pakai user_fcm_tokens
--
-- Sebelumnya fungsi-fungsi ini baca `profiles.fcm_token` SAJA (legacy,
-- dikosongkan 20260827000000) → panggilan masuk / notif online / broadcast
-- TIDAK sampai ke device klien baru. Sekarang pakai helper terpusat
-- public.user_fcm_tokens() (user_devices + fallback profiles bila kosong).
--
-- Menyentuh: call_push (overload 6-arg). call_push TIDAK ada di
-- frozen_functions.txt, tapi diberi header demi kejelasan.
-- notify_contact_online & notify_broadcast_started juga TIDAK frozen.
--
-- Payload notif TIDAK berubah (hanya sumber token yang diganti).
--
-- ROLLBACK: re-apply definisi lama (lihat MIGRATION_LOG 2026-09-27).
-- ============================================================

-- ── call_push (6-arg): fan-out ke semua device aktif + fallback ─────────────
-- menyentuh: call_push
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text,
  p_call_type text, p_avatar text default ''
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  t text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
  v_chat_id text;
  v_msg text;
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  v_msg := case when p_call_type = 'video' then 'Panggilan video' else 'Panggilan suara' end;
  for t in select public.user_fcm_tokens(p_callee) loop
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
  end loop;
end; $function$;

-- ── notify_contact_online: token dari helper ────────────────────────────────
create or replace function public.notify_contact_online()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  contact_id uuid;
  contact_chat text;
  t text;
begin
  if new.status <> 'online' or old.status = 'online' then return new; end if;
  for contact_id, contact_chat in
    select distinct u as uid, pc.chat_id
      from public.private_chats pc
      cross join lateral unnest(pc.participants) as u
     where new.id = any (pc.participants) and u <> new.id
  loop
    for t in select public.user_fcm_tokens(contact_id) loop
      begin
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type','application/json','x-app-secret',(select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'title', coalesce(new.nickname,'Anon'),
            'body', 'is online',
            'data', jsonb_build_object(
              'type','online','chatId',contact_chat,
              'otherUid',new.id,'otherName',coalesce(new.nickname,'Anon')
            )
          )
        );
      exception when others then null;
      end;
    end loop;
  end loop;
  return new;
exception when others then return new;
end; $function$;

-- ── notify_broadcast_started: token dari helper ─────────────────────────────
create or replace function public.notify_broadcast_started()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  b_name text;
  r_name text;
  t text;
  v_uid uuid;
begin
  begin
    select coalesce(nickname, name, 'Anon') into b_name
      from public.profiles where id = new.user_id;
    select name into r_name from public.rooms where id = new.room_id;

    for v_uid in
      select m.user_id
        from public.room_members m
       where m.room_id = new.room_id
         and m.user_id <> new.user_id
    loop
      for t in select public.user_fcm_tokens(v_uid) loop
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'data', jsonb_build_object(
              'type', 'broadcast',
              'roomId', new.room_id,
              'roomName', coalesce(r_name, 'Room'),
              'ownerId', new.user_id,
              'otherUid', new.user_id,
              'otherName', coalesce(b_name, 'Anon')
            )
          )
        );
      end loop;
    end loop;
  exception when others then
    null;
  end;
  return new;
end; $function$;

-- Verifikasi:
--   select proname from pg_proc where proname in ('call_push','notify_contact_online','notify_broadcast_started');
--   select pg_get_functiondef(oid) like '%user_fcm_tokens%' from pg_proc where proname='call_push';
