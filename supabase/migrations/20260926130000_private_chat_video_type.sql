-- ============================================================
-- Video di private chat: type='video' + preview notif '[Video]'.
--
-- LATAR: private chat sudah bisa kirim foto/view-once/voice, belum video.
-- Infrastruktur upload/kompres video sudah ada (dipakai story video:
-- `chat_photos_guard` sudah mengizinkan video/mp4 ≤20 MB di bucket
-- chat-photos), tapi kolom `private_messages.type` masih menolak 'video'
-- lewat CHECK constraint → insert gagal diam-diam.
--
-- PERUBAHAN:
--   1) private_messages_type_check: + 'video'.
--      Dasar = migrasi terakhir 20260901050001_voice_type_check.sql
--      (teks[], bukan `in (...)` — samakan bentuk persisnya).
--   2) notify_private_message (FROZEN): body preview ditambah cabang
--      video → '[Video]' supaya notifikasi tidak kosong.
--      Dasar = definisi live/snapshot 20260913130001_notif_touid.sql.
--   3) message_cache version bump TIDAK perlu (tipe baru, bukan skema
--      kolom) — cache lama tetap valid, hanya menambah varian type.
--
-- menyentuh: notify_private_message
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

-- ── 1. CHECK constraint: izinkan type='video' ──
alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check
  check (type = any (array[
    'text'::text, 'image'::text, 'view_once'::text, 'view_once_expired'::text,
    'coin'::text, 'gift'::text, 'call'::text, 'voice'::text, 'video'::text
  ]));

-- ── 2. notify_private_message: preview '[Video]' ──
-- Definisi SAMA dengan 20260913130001, hanya menambah satu cabang case.
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
    -- DITAMBAH: video → '[Video]'.
    v_body := case when new.type in ('image','view_once') then '[Foto]'
                   when new.type = 'video' then '[Video]'
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
end; $function$
