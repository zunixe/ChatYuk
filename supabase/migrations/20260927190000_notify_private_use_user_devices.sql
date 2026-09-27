-- ============================================================
-- Langkah 1 (c): notify_private_message → token dari user_fcm_tokens
--
-- menyentuh: notify_private_message (FROZEN)
--
-- Dasar = versi outbox (20260927160000). Perubahan: token penerima diambil
-- dari helper public.user_fcm_tokens() (user_devices + fallback profiles)
-- & di-loop → pesan 1:1 sampai ke SEMUA device aktif (klien baru).
-- Payload & logika lain 100% IDENTIK. Tetap insert ke outbox (bukan http).
--
-- Snapshot DI-REGEN setelah apply.
-- ROLLBACK: re-apply 20260927160000_notify_private_via_outbox.sql.
-- ============================================================

create or replace function public.notify_private_message()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
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
      select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
      sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
      for receiver_token in select public.user_fcm_tokens(receiver_id) loop
        insert into public.outbox (type, payload)
        values ('push', jsonb_build_object(
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
        ));
      end loop;
      return new;
    end if;

    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is null then return new; end if;
    select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
    sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
    -- Preview isi: teks (200 char) atau label tipe non-teks.
    v_body := case when new.type in ('image','view_once') then '[Foto]'
                   when new.type in ('video','video_once','video_once_expired')
                     then '[Video]'
                   when new.type = 'voice' then '[Pesan suara]'
                   when new.type = 'coin' then '[Koin]'
                   when new.type = 'gift' then '[Hadiah]'
                   else left(coalesce(new.text,''), 200) end;
    for receiver_token in select public.user_fcm_tokens(receiver_id) loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
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
      ));
    end loop;
  exception when others then null;
  end;
  return new;
end; $function$;

-- Verifikasi:
--   select pg_get_functiondef(oid) like '%user_fcm_tokens%' from pg_proc where proname='notify_private_message';
