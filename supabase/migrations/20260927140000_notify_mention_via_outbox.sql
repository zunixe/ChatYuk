-- ============================================================
-- Outbox Fase B: notify_mention_room → outbox (bukan net.http_post sinkron)
--
-- Dasar = definisi LIVE saat ini (pg_get_functiondef, versi terbaru).
-- Perubahan HANYA cara kirim: `perform net.http_post(...)` →
-- `insert into public.outbox (type, payload) values ('push', <body sama>)`.
-- Logika lain 100% IDENTIK:
--   - guard mentions null/kosong
--   - sender_display / sender_avatar / room_name / v_body
--   - loop token dari user_devices
--   - fallback profiles.fcm_token bila tak ada baris user_devices
--
-- Payload outbox = body yang dulu dikirim ke send-push apa adanya:
--   { token, title, body, data:{...} }  → worker meneruskan ke send-push.
--
-- CATATAN: notify_mention_room TIDAK ada di scripts/frozen_functions.txt →
-- bukan FROZEN (tidak butuh header '-- menyentuh:').
--
-- PENTING: cron outbox-worker WAJIB aktif, kalau tidak mention tidak terkirim.
-- (Lihat migrasi 20260927140000_outbox_worker_cron.sql.)
-- ============================================================

create or replace function public.notify_mention_room()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  rec record;
  sender_display text;
  sender_avatar text;
  room_name text;
  v_body text;
begin
  begin
    -- Hanya saat ada mention; selain itu trigger tidak melakukan apa pun.
    if new.mentions is null
       or jsonb_typeof(new.mentions) <> 'array'
       or jsonb_array_length(new.mentions) = 0 then
      return new;
    end if;

    select coalesce(nullif(nickname,''), nullif(new.sender_name,''), 'User'), avatar
      into sender_display, sender_avatar
      from public.profiles where id = new.sender_id;
    sender_display := coalesce(sender_display, 'User');

    select coalesce(nullif(name,''), 'Room') into room_name
      from public.rooms where id = new.room_id;
    room_name := coalesce(room_name, 'Room');

    v_body := case
      when new.type in ('image','view_once') then sender_display || ' menyebutmu · [Foto]'
      when new.type = 'voice' then sender_display || ' menyebutmu · [Pesan suara]'
      when new.type = 'gift' then sender_display || ' menyebutmu · [Hadiah]'
      else sender_display || ': ' || left(coalesce(new.text,''), 160)
    end;

    for rec in
      select distinct d.fcm_token as token, (m->>'uid')::uuid as uid
        from jsonb_array_elements(new.mentions) as m
        join public.user_devices d
          on d.user_id = (m->>'uid')::uuid
         and d.is_active = true
         and coalesce(d.fcm_token,'') <> ''
       where (m->>'uid')::uuid <> new.sender_id
    loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
        'token', rec.token,
        'title', room_name,
        'body', v_body,
        'data', jsonb_build_object(
          'type', 'mention',
          'toUid', rec.uid,
          'chatId', new.room_id,
          'roomId', new.room_id,
          'roomName', room_name,
          'otherUid', new.sender_id,
          'otherName', sender_display,
          'avatarUrl', coalesce(sender_avatar,''),
          'message', v_body,
          'body', v_body
        )
      ));
    end loop;

    -- Fallback (klien lama tanpa baris user_devices): profiles.fcm_token.
    if not exists (
      select 1 from public.user_devices d
       join jsonb_array_elements(new.mentions) as m on d.user_id = (m->>'uid')::uuid
       where d.is_active = true and coalesce(d.fcm_token,'') <> ''
    ) then
      for rec in
        select p.fcm_token as token, p.id as uid
          from public.profiles p
          join jsonb_array_elements(new.mentions) as m on p.id = (m->>'uid')::uuid
         where p.id <> new.sender_id and coalesce(p.fcm_token,'') <> ''
      loop
        insert into public.outbox (type, payload)
        values ('push', jsonb_build_object(
          'token', rec.token,
          'title', room_name,
          'body', v_body,
          'data', jsonb_build_object(
            'type', 'mention',
            'toUid', rec.uid,
            'chatId', new.room_id,
            'roomId', new.room_id,
            'roomName', room_name,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'avatarUrl', coalesce(sender_avatar,''),
            'message', v_body,
            'body', v_body
          )
        ));
      end loop;
    end if;
  exception when others then null;
  end;
  return new;
end;
$function$;

-- Verifikasi:
--   select pg_get_functiondef(oid) from pg_proc where proname='notify_mention_room'
--     → harus ada 'insert into public.outbox', TIDAK ada 'net.http_post'.
-- ROLLBACK: re-apply definisi lama dari migrasi 20260921120000_mentions.sql.
