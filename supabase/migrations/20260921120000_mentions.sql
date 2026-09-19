-- ============================================================
-- Fitur mention @ di chat (private, grup/private room, global room).
--
-- Penyimpanan: kolom `mentions` jsonb pada kedua tabel pesan.
--   Format: [{"uid":"<uuid>","name":"<nickname saat kirim>"}]
--   Nama disimpan apa adanya supaya highlight tidak berubah saat rename.
--
-- Notifikasi: room/group TIDAK punya push per-pesan (hanya mention ini).
--   Trigger notify_mention_room() mengirim push TERARAH hanya ke uid yang
--   di-mention (mute per-chat dihormati di klien). Private 1:1 tidak
--   memakai trigger ini — sudah ada notify_private_message.
--
-- TIDAK menyentuh fungsi FROZEN apa pun.
-- ============================================================

alter table public.messages
  add column if not exists mentions jsonb not null default '[]'::jsonb;
alter table public.private_messages
  add column if not exists mentions jsonb not null default '[]'::jsonb;

-- ── Trigger: push terarah ke setiap uid yang di-mention (room/group) ──
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
      begin
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-app-secret', (select app_shared_secret from app_settings where id = 'global')
          ),
          body := jsonb_build_object(
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
          )
        );
      exception when others then null;
      end;
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
        begin
          perform net.http_post(
            url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'x-app-secret', (select app_shared_secret from app_settings where id = 'global')
            ),
            body := jsonb_build_object(
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
            )
          );
        exception when others then null;
        end;
      end loop;
    end if;
  exception when others then null;
  end;
  return new;
end;
$function$;

drop trigger if exists notify_mention_room_trg on public.messages;
create trigger notify_mention_room_trg
  after insert on public.messages
  for each row execute function public.notify_mention_room();
