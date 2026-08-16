-- ============================================================
-- ChatYuk: Transfer koin antar user di private chat
--
-- Aturan:
--   - HANYA pengirim terdaftar (is_registered = true) yang boleh kirim
--     (anti-farming: akun anonim dapat 50 koin gratis).
--   - jumlah 5..1000, integer, pengirim != penerima.
--   - keduanya harus peserta chat_id, dan tidak saling blokir.
--   - tanpa biaya transfer (yang dikirim = yang diterima).
--   - pesan type 'coin' dibuat SERVER (client tidak bisa palsukan nominal).
-- ============================================================

-- Update trigger preview last_message agar type 'coin' & 'view_once' benar
create or replace function public.handle_new_private_message() returns trigger as $$
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
      else new.text end,
    last_message_at = now(),
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $$ language plpgsql security definer;

-- ============================================================
-- RPC: send_coins
-- ============================================================
create or replace function public.send_coins(
  p_chat_id text,
  p_receiver_id uuid,
  p_amount int
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  am_registered boolean;
  remaining int;
  my_name text;
  my_gender text;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_amount is null or p_amount < 5 or p_amount > 1000 then
    raise exception 'Invalid amount';
  end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  -- pengirim wajib terdaftar
  select is_registered, nickname, gender
    into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then
    raise exception 'Sender must be registered';
  end if;

  -- keduanya peserta chat
  if not exists (
    select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id
      and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)
  ) then
    raise exception 'Not a chat participant';
  end if;

  -- tidak saling blokir
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)
  ) then
    raise exception 'Blocked';
  end if;

  -- saldo cukup
  select points into remaining from public.profiles where id = uid;
  if coalesce(remaining, 0) < p_amount then
    raise exception 'Not enough points';
  end if;

  -- transfer atomik
  update public.profiles set points = points - p_amount where id = uid
    returning points into remaining;
  update public.profiles set points = points + p_amount where id = p_receiver_id;

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', p_amount);

  -- pesan bukti transfer (nominal disimpan di text)
  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0));
end;
$$;

revoke execute on function public.send_coins(text, uuid, int) from public, anon;
grant execute on function public.send_coins(text, uuid, int) to authenticated;
