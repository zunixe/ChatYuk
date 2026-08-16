-- Admin/dev bypass (extended): semua guard points_enabled (hard & soft)
-- dikecualikan untuk admin (zunixe@gmail.com). Saat points_enabled = false:
--   - user biasa: aktivitas koin dibekukan seperti biasa (production aman)
--   - admin/developer: bisa menguji gift, withdraw, bonus, quest, dll.
-- daily_login_bonus (versi jsonb/streak) juga diberi guard + exemption.
begin;
-- [1] new_chat_bonus
create or replace function public.new_chat_bonus(other_uid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; tot int; ok boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  if exists (select 1 from point_events where user_id = auth.uid()
             and event = 'new_chat' and metadata->>'other_uid' = other_uid::text) then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set new_chats_today = new_chats_today + 1
    where id = auth.uid() and new_chats_today < 3;
  ok := found;

  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'new_chat', 5,
             null, jsonb_build_object('other_uid', other_uid));
    insert into point_events (user_id, event, amount, metadata)
      values (auth.uid(), 'new_chat', 5, jsonb_build_object('other_uid', other_uid));
    return tot;
  end if;

  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
-- [2] room_read_bonus
create or replace function public.room_read_bonus()
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; ok boolean; tot int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set room_reads_today = room_reads_today + 1
    where id = auth.uid() and room_reads_today < 5;
  ok := found;

  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'room_read', 2);
    insert into point_events (user_id, event, amount)
      values (auth.uid(), 'room_read', 2);
    return tot;
  end if;

  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
-- [3] one_time_bonus
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int language plpgsql security definer set search_path = public as $$
declare valid_actions text[]; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  valid_actions := array['registered','rated_app','completed_profile',
    'shared_app','invited_friend','first_photo','first_room_chat',
    'online_5min','online_30min','online_60min','online_120min'];
  if not (action_key = any(valid_actions)) then
    raise exception 'Invalid action key: %', action_key;
  end if;

  if exists (select 1 from profiles where id = auth.uid()
             and one_time_actions->>action_key = 'true') then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
    where id = auth.uid();

  tot := public.ledger_credit(auth.uid(), 'bonus', 'one_time', bonus,
           null, jsonb_build_object('action', action_key));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'bonus', bonus, jsonb_build_object('action', action_key));

  return tot;
end; $$;
-- [4] send_coins
create or replace function public.send_coins(
  p_chat_id text, p_receiver_id uuid, p_amount int
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
  b int; t int; e int; need int; take_bonus int := 0; take_topup int := 0; take_earned int := 0;
  recv_earned int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then raise exception 'Points system disabled'; end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  -- Anti-spam: batas transaksi coin/gift per jam
  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;

  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- hitung porsi tiap bucket pengirim (urutan bonus→topup→earned)
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = uid;
  if (b + t + e) < p_amount then raise exception 'Not enough points'; end if;

  need := p_amount;
  take_bonus  := least(b, need); need := need - take_bonus;
  take_topup  := least(t, need); need := need - take_topup;
  take_earned := least(e, need); need := need - take_earned;

  -- debit pengirim per bucket
  if take_bonus > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (uid,'bonus','coin_sent',-take_bonus,p_chat_id); end if;
  if take_topup > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (uid,'topup','coin_sent',-take_topup,p_chat_id); end if;
  if take_earned > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (uid,'earned','coin_sent',-take_earned,p_chat_id); end if;
  remaining := public.wallet_sync_points(uid);

  -- kredit penerima: bonus→bonus, (topup+earned)→earned
  if take_bonus > 0 then
    perform public.ledger_credit(p_receiver_id,'bonus','coin_received',take_bonus,p_chat_id,
      jsonb_build_object('from', uid)); end if;
  recv_earned := take_topup + take_earned;
  if recv_earned > 0 then
    perform public.ledger_credit(p_receiver_id,'earned','coin_received',recv_earned,p_chat_id,
      jsonb_build_object('from', uid)); end if;

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', p_amount);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0));
end; $$;
-- [5] claim_weekly_quest
create or replace function public.claim_weekly_quest(quest_key text, tz_offset_minutes int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare wk_start timestamptz; wk text; progress int; target int; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return jsonb_build_object('points', coalesce(tot,0), 'claimed', false);
  end if;

  if quest_key not in ('w_login','w_social','w_active') then
    raise exception 'Invalid quest key: %', quest_key;
  end if;

  wk_start := public.week_start_utc(tz_offset_minutes);
  wk := public.week_label(tz_offset_minutes);

  if exists (select 1 from point_events where user_id = auth.uid()
    and event = 'weekly_quest' and metadata->>'key' = quest_key and metadata->>'week' = wk) then
    select points into tot from profiles where id = auth.uid();
    return jsonb_build_object('points', coalesce(tot,0), 'claimed', false);
  end if;

  if quest_key = 'w_login' then
    select count(distinct (created_at + make_interval(mins => tz_offset_minutes))::date)
      into progress from point_events
      where user_id = auth.uid() and event = 'daily_login' and created_at >= wk_start;
    target := 5;
  elsif quest_key = 'w_social' then
    select count(*) into progress from point_events
      where user_id = auth.uid() and event = 'new_chat' and created_at >= wk_start;
    target := 10;
  else
    select count(*) into progress from point_events
      where user_id = auth.uid() and event = 'deduct' and created_at >= wk_start;
    target := 100;
  end if;

  if progress < target then
    raise exception 'Quest not completed: % (%/%)', quest_key, progress, target;
  end if;

  tot := public.ledger_credit(auth.uid(), 'bonus', 'weekly_quest', 50,
           null, jsonb_build_object('key', quest_key, 'week', wk));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'weekly_quest', 50, jsonb_build_object('key', quest_key, 'week', wk));

  return jsonb_build_object('points', tot, 'claimed', true);
end; $$;
-- [6] deduct_chat_point
create or replace function public.deduct_chat_point(msg_type text)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; cost int; remaining int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;

  cost := case msg_type
    when 'image' then 3 when 'view_once' then 3
    when 'view_once_expired' then 0 else 1 end;

  if cost = 0 then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;

  remaining := public.ledger_spend(auth.uid(), 'spend_chat', cost, msg_type);

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));

  return remaining;
end; $$;
-- [7] join_private_room
create or replace function public.join_private_room(
  p_room_id text,
  p_password text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  r record;
  points_on boolean;
  am_registered boolean;
  remaining int;
  charged int := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into r from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found';
  end if;

  -- room kedaluwarsa
  if r.is_private and r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;

  -- bukan private, atau owner, atau sudah member → gratis
  if not r.is_private or r.owner_id = uid
     or exists (select 1 from public.room_members m
                where m.room_id = p_room_id and m.user_id = uid) then
    insert into public.room_members (room_id, user_id) values (p_room_id, uid)
      on conflict do nothing;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0));
  end if;

  -- verifikasi password DULU (sebelum menyentuh koin)
  if r.has_password then
    if p_password is null or r.password_hash is null
       or crypt(p_password, r.password_hash) <> r.password_hash then
      raise exception 'Wrong password';
    end if;
  end if;

  select points_enabled into points_on from public.app_settings where id = 'global';

  if points_on is not false or coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    select points into remaining from public.profiles where id = uid;
    if coalesce(remaining, 0) < 5 then
      raise exception 'Not enough points';
    end if;
    update public.profiles set points = points - 5 where id = uid
      returning points into remaining;
    charged := 5;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_join', -5);

    -- fee ke owner HANYA jika joiner terdaftar (anti-farming akun anonim)
    select is_registered into am_registered from public.profiles where id = uid;
    if am_registered is true and r.owner_id is not null and r.owner_id <> uid then
      update public.profiles set points = points + 5 where id = r.owner_id;
      insert into public.point_events (user_id, event, amount)
        values (r.owner_id, 'private_room_income', 5);
    end if;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  insert into public.room_members (room_id, user_id) values (p_room_id, uid)
    on conflict do nothing;

  return jsonb_build_object('ok', true, 'charged', charged, 'points', coalesce(remaining, 0));
end;
$$;
-- [8] extend_private_room
create or replace function public.extend_private_room(p_room_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  r record;
  points_on boolean;
  remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;

  select points_enabled into points_on from public.app_settings where id = 'global';
  if points_on is not false or coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    select points into remaining from public.profiles where id = uid;
    if coalesce(remaining, 0) < 50 then
      raise exception 'Not enough points';
    end if;
    update public.profiles set points = points - 50 where id = uid
      returning points into remaining;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_extend', -50);
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  update public.rooms
    set expires_at = greatest(coalesce(expires_at, now()), now()) + interval '7 days'
    where id = p_room_id
    returning expires_at into r.expires_at;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
                            'expires_at', r.expires_at);
end;
$$;
-- [9] send_gift
create or replace function public.send_gift(
  p_chat_id text, p_receiver_id uuid, p_gift_id text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int;
  my_name text; my_gender text;
  b int; t int; e int; need int;
  pay_bonus int := 0; pay_topup int := 0; pay_earned int := 0;
  n int; cut int; net int;
  earn_src int;
  recv_earned int; recv_bonus int; remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;

  select points_enabled, coalesce(gift_cut_pct,30) into points_on, cut_pct
    from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then raise exception 'Points system disabled'; end if;

  -- Anti-spam: batas transaksi coin/gift per jam
  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins;

  -- peserta chat & tidak saling blokir
  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;
  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- saldo & porsi bucket pengirim
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = uid;
  if (b + t + e) < n then raise exception 'Not enough points'; end if;

  need := n;
  pay_bonus  := least(b, need); need := need - pay_bonus;
  pay_topup  := least(t, need); need := need - pay_topup;
  pay_earned := least(e, need); need := need - pay_earned;

  -- debit pengirim per bucket
  if pay_bonus > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'bonus','gift_sent',-pay_bonus,p_chat_id,jsonb_build_object('gift',p_gift_id)); end if;
  if pay_topup > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'topup','gift_sent',-pay_topup,p_chat_id,jsonb_build_object('gift',p_gift_id)); end if;
  if pay_earned > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'earned','gift_sent',-pay_earned,p_chat_id,jsonb_build_object('gift',p_gift_id)); end if;
  remaining := public.wallet_sync_points(uid);

  -- platform cut
  cut := (n * cut_pct) / 100;
  net := n - cut;

  -- pembagian net ke penerima, lineage proporsional
  earn_src := pay_topup + pay_earned;
  if net <= 0 then
    recv_earned := 0; recv_bonus := 0;
  elsif earn_src = 0 then
    recv_earned := 0; recv_bonus := net;
  elsif pay_bonus = 0 then
    recv_earned := net; recv_bonus := 0;
  else
    recv_earned := (net * earn_src) / n;
    recv_bonus  := net - recv_earned;
  end if;

  if recv_earned > 0 then
    perform public.ledger_credit(p_receiver_id,'earned','gift_recv',recv_earned,p_chat_id,
      jsonb_build_object('gift',p_gift_id,'from',uid)); end if;
  if recv_bonus > 0 then
    perform public.ledger_credit(p_receiver_id,'bonus','gift_recv',recv_bonus,p_chat_id,
      jsonb_build_object('gift',p_gift_id,'from',uid)); end if;

  -- catat profit platform
  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
              jsonb_build_object('gift',p_gift_id,'gross',n,'net',net,'pct',cut_pct));
  end if;

  -- point_events untuk analitik/leaderboard (pakai net di penerima)
  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n, jsonb_build_object('gift',p_gift_id)),
           (p_receiver_id, 'gift_recv', net, jsonb_build_object('gift',p_gift_id));

  -- pesan bukti gift
  select nickname, gender into my_name, my_gender from public.profiles where id = uid;
  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut);
end; $$;
-- [10] request_withdrawal
create or replace function public.request_withdrawal(
  p_coin_amount int, p_pay_method text, p_pay_account text, p_pay_holder text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  points_on boolean; rate int; min_coins int;
  min_age_h int; max_day int; min_interval_h int;
  earned int; payout int; acct_age_h int; last_req timestamptz;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled, withdraw_rate_idr, withdraw_min_coins,
         withdraw_min_account_age_hours, withdraw_max_per_day, withdraw_min_interval_hours
    into points_on, rate, min_coins, min_age_h, max_day, min_interval_h
    from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then raise exception 'Points system disabled'; end if;

  -- KYC wajib sudah disetujui
  if not exists (select 1 from kyc_requests k
                 where k.user_id = uid and k.status = 'approved') then
    raise exception 'KYC required';
  end if;

  -- Anti-fraud: umur akun minimal
  select floor(extract(epoch from (now() - p.created_at)) / 3600)::int
    into acct_age_h from profiles p where p.id = uid;
  if acct_age_h < min_age_h then raise exception 'Account too new'; end if;

  -- Anti-fraud: batas harian
  if (select count(*) from withdrawal_requests
      where user_id = uid and created_at >= date_trunc('day', now())) >= max_day then
    raise exception 'Daily limit reached';
  end if;

  -- Anti-fraud: jeda minimum antar request
  select max(created_at) into last_req from withdrawal_requests where user_id = uid;
  if last_req is not null
     and last_req > now() - make_interval(hours => min_interval_h) then
    raise exception 'Too frequent';
  end if;

  if p_coin_amount is null or p_coin_amount < min_coins then
    raise exception 'Below minimum'; end if;
  if length(trim(p_pay_account)) < 5 or length(trim(p_pay_holder)) < 3 then
    raise exception 'Invalid payout info'; end if;

  -- hanya earned yang bisa dicairkan
  select coalesce(sum(amount) filter (where bucket='earned'),0)
    into earned from coin_ledger where user_id = uid;
  if earned < p_coin_amount then raise exception 'Not enough withdrawable'; end if;

  payout := p_coin_amount * rate;

  -- debit earned (hold) — jika ditolak admin, direfund
  insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
    values (uid,'earned','withdraw_request',-p_coin_amount,
            p_pay_method, jsonb_build_object('payout_idr',payout));
  perform public.wallet_sync_points(uid);

  insert into withdrawal_requests (user_id, coin_amount, payout_idr, rate, status,
                                   pay_method, pay_account, pay_holder)
  values (uid, p_coin_amount, payout, rate, 'pending',
          p_pay_method, trim(p_pay_account), trim(p_pay_holder));

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'withdraw_request', -p_coin_amount,
            jsonb_build_object('payout_idr',payout));

  return jsonb_build_object('ok', true, 'coin_amount', p_coin_amount,
    'payout_idr', payout, 'status', 'pending', 'rate', rate);
end; $$;
-- [11] create_private_room
create or replace function public.create_private_room(
  p_name text,
  p_icon text,
  p_country text,
  p_password text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  points_on boolean;
  cost int;
  has_pw boolean := (p_password is not null and length(p_password) > 0);
  active_count int;
  new_id text;
  my_name text;
  remaining int;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then
    raise exception 'Invalid room name';
  end if;
  if p_country is null or p_country = '' then
    raise exception 'Invalid country';
  end if;

  -- limit 2 room aktif per user
  select count(*) into active_count from public.rooms
   where owner_id = uid and is_private = true
     and (expires_at is null or expires_at > now());
  if active_count >= 2 then
    raise exception 'Room limit reached';
  end if;

  select points_enabled into points_on from public.app_settings where id = 'global';
  cost := case when has_pw then 150 else 100 end;

  if points_on is not false or coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    select points into remaining from public.profiles where id = uid;
    if coalesce(remaining, 0) < cost then
      raise exception 'Not enough points';
    end if;
    update public.profiles set points = points - cost where id = uid
      returning points into remaining;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_create', -cost);
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  select nickname into my_name from public.profiles where id = uid;
  new_id := 'pr_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.rooms (id, name, description, icon, "order", country, category,
                            is_private, owner_id, owner_name, password_hash, has_password,
                            expires_at, created_at)
  values (new_id, p_name, '', coalesce(nullif(p_icon, ''), '🔒'), 999, p_country, 'private',
          true, uid, coalesce(my_name, 'Anon'),
          case when has_pw then crypt(p_password, gen_salt('bf')) else null end,
          has_pw, now() + interval '7 days', now());

  insert into public.room_members (room_id, user_id) values (new_id, uid)
    on conflict do nothing;

  return jsonb_build_object('id', new_id, 'points', coalesce(remaining, 0));
end;
$$;
-- [12] daily_login_bonus
create or replace function public.daily_login_bonus()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  today date;
  last_date date;
  cur_points int;
  cur_streak int;
  new_streak int;
  bonus int;
  r int;
  points_on boolean;
begin
  today := (now() at time zone 'Asia/Jakarta')::date;

  select last_login_date, points, login_streak
    into last_date, cur_points, cur_streak
    from profiles where id = auth.uid();

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    return jsonb_build_object('points', coalesce(cur_points, 0), 'streak', coalesce(cur_streak, 0), 'bonus', 0);
  end if;

  -- Sudah klaim hari ini → idempotent, tidak menambah poin
  if last_date is not null and last_date >= today then
    return jsonb_build_object(
      'points', coalesce(cur_points, 0),
      'streak', coalesce(cur_streak, 0),
      'bonus', 0
    );
  end if;

  -- Hitung streak baru
  if last_date is not null and last_date = today - 1 then
    new_streak := coalesce(cur_streak, 0) + 1;
    -- Setelah hari ke-7 (bonus mingguan), siklus ulang ke 1
    if new_streak > 7 then
      new_streak := 1;
    end if;
  else
    new_streak := 1; -- pertama kali atau streak putus
  end if;

  bonus := public.streak_bonus_amount(new_streak);

  update profiles set
    points = points + bonus,
    login_streak = new_streak,
    last_login_date = today,
    login_at = now(),
    room_reads_today = 0,
    new_chats_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min'
    ]
  where id = auth.uid()
  returning points into r;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'daily_login', bonus,
            jsonb_build_object('streak', new_streak));

  return jsonb_build_object('points', r, 'streak', new_streak, 'bonus', bonus);
end;
$$;
commit;
