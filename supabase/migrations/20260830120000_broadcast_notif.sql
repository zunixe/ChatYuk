-- ============================================================
-- Notifikasi push saat ada member mulai broadcast di room.
-- Trigger room_broadcasters AFTER INSERT (start_broadcast RPC):
-- kirim FCM data-only type 'broadcast' ke semua member room
-- (kecuali broadcaster sendiri). Tap notif → client buka
-- RoomChatScreen langsung (ditangani _openFromData di main.dart).
-- ============================================================

create or replace function public.notify_broadcast_started()
returns trigger as $$
declare
  b_name text;
  r_name text;
  t text;
begin
  begin
    select coalesce(nickname, name, 'Anon') into b_name
      from public.profiles where id = new.user_id;
    select name into r_name from public.rooms where id = new.room_id;

    for t in
      select p.fcm_token
      from public.room_members m
      join public.profiles p on p.id = m.user_id
      where m.room_id = new.room_id
        and m.user_id <> new.user_id
        and p.fcm_token is not null
        and p.fcm_token <> ''
    loop
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json'),
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
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;

drop trigger if exists notify_broadcast_started_trigger on public.room_broadcasters;
create trigger notify_broadcast_started_trigger
  after insert on public.room_broadcasters
  for each row
  execute function public.notify_broadcast_started();
