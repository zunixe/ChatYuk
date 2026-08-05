create or replace function public.notify_private_message() returns trigger as $$
declare
  receiver_id uuid;
  receiver_token text;
begin
  begin
    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is not null then
      select fcm_token into receiver_token from public.profiles where id = receiver_id;
      if receiver_token is not null and receiver_token <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json'),
          body := jsonb_build_object('token', receiver_token, 'title', new.sender_name, 'body', case when new.type = 'image' then '[Foto]' else new.text end, 'data', jsonb_build_object('chatId', new.chat_id, 'otherName', new.sender_name, 'otherUid', new.sender_id))
        );
      end if;
    end if;
  exception when others then
    null;
  end;
  return new;
end; $$ language plpgsql security definer;
