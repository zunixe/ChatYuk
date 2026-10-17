-- menyentuh: handle_new_private_message
-- menyentuh: notify_private_message
--
-- Label media di last_message & body notifikasi private chat.
-- Basis = versi LIVE (diverifikasi identik dgn supabase/snapshots/functions.sql
-- pada 2026-10-18). HANYA menambah cabang `when` — tidak ada cabang dihapus.
--
-- Bug: stiker/voice/video-tanpa-caption punya text '' → last_message '' →
-- daftar chat "Belum ada pesan" padahal ada pesan; notif stiker body kosong,
-- notif lokasi berisi JSON koordinat mentah.

create or replace function public.handle_new_private_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  receiver uuid;
  unread jsonb := '{}'::jsonb;
  lastread jsonb := '{}'::jsonb;
begin
  select p2 into receiver from (
    select unnest(participants) as p2 from public.private_chats where chat_id = new.chat_id
  ) x where p2 <> new.sender_id limit 1;
  if receiver is null then return new; end if;

  select coalesce(unread_counts, '{}'::jsonb) into unread from public.private_chats where chat_id = new.chat_id;
  if unread is null then unread := '{}'::jsonb; end if;
  unread := jsonb_set(unread, array[receiver::text], to_jsonb(coalesce((unread->>receiver::text)::int, 0) + 1), true);

  select coalesce(last_read_at, '{}'::jsonb) into lastread from public.private_chats where chat_id = new.chat_id;
  if lastread is null then lastread := '{}'::jsonb; end if;

  update public.private_chats set
    last_message = case
      when new.type = 'image' then '[Foto]'
      when new.type = 'view_once' then '[Foto]'
      when new.type = 'coin' then '[Koin]'
      when new.type = 'gift' then '[Hadiah]'
      -- 2026-10-18: tipe ber-teks kosong dulu jatuh ke else ('') → daftar
      -- chat tampil "Belum ada pesan". Video BERCAPTION tetap pakai caption.
      when new.type = 'sticker' then '[Stiker]'
      when new.type = 'voice' then '[Pesan suara]'
      when new.type in ('video','video_once','video_once_expired')
        and coalesce(new.text,'') = '' then '[Video]'
      else new.text end,
    last_message_at = now(),
    last_sender_id = new.sender_id,
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $function$;

create or replace function public.notify_private_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
                   -- 2026-10-18: stiker dulu body kosong; lokasi dulu JSON
                   -- koordinat mentah di notifikasi.
                   when new.type = 'sticker' then '[Stiker]'
                   when new.type = 'location' then '[Lokasi]'
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
