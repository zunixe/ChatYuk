-- ============================================================
-- Outbox Fase C: notify_private_message → outbox (bukan net.http_post sinkron)
--
-- menyentuh: notify_private_message
--
-- Dasar = definisi LIVE terbaru (pg_get_functiondef). Perubahan HANYA cara
-- kirim: `perform net.http_post(...)` → `insert into public.outbox`.
-- Logika lain 100% IDENTIK:
--   - cabang type='call' (dedup 30 dtk, missed_call)
--   - receive dari participants, guard receiver_token
--   - sender_display / sender_avatar
--   - v_body preview tipe (image/video/voice/coin/gift/teks 200 char)
--   - struktur data jsonb persis sama
--
-- Ada DUA jalur http_post di fungsi ini (call & pesan biasa) → keduanya
-- dipindah ke outbox dengan payload IDENTIK.
--
-- PENTING: cron outbox-worker WAJIB aktif (20260927150000).
-- Snapshot supabase/snapshots/functions.sql DI-REGEN setelah apply.
--
-- ROLLBACK: re-apply definisi lama (/tmp/notify_private_message_LIVE.sql)
--   atau migrasi terakhir penyentuh: 20260926150000_notif_video_label.sql.
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
      select fcm_token into receiver_token from public.profiles where id = receiver_id;
      if receiver_token is null or receiver_token = '' then return new; end if;
      select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
      sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
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
                   when new.type in ('video','video_once','video_once_expired')
                     then '[Video]'
                   when new.type = 'voice' then '[Pesan suara]'
                   when new.type = 'coin' then '[Koin]'
                   when new.type = 'gift' then '[Hadiah]'
                   else left(coalesce(new.text,''), 200) end;
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
  exception when others then null;
  end;
  return new;
end; $function$;

-- Verifikasi:
--   select pg_get_functiondef(oid) from pg_proc where proname='notify_private_message'
--     → harus ada 'insert into public.outbox', TIDAK ada 'net.http_post'.
