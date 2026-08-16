-- ============================================================
-- ChatYuk Wallet FASE 6 — Anti-Fraud & Rate Limits
--
-- Melindungi sisi keluar uang (withdrawal) + membatasi spam/carding:
--   - Akun harus berumur minimal sebelum bisa mencairkan.
--   - Batas jumlah pencairan per hari & jeda minimum antar request.
--   - Batas transaksi coin/gift per jam (anti spam & farming).
-- Semua ambang bisa diubah admin lewat app_settings.
-- ============================================================

alter table public.app_settings
  add column if not exists withdraw_min_account_age_hours int not null default 72,
  add column if not exists withdraw_max_per_day          int not null default 3,
  add column if not exists withdraw_min_interval_hours   int not null default 1,
  add column if not exists coin_tx_max_per_hour          int not null default 30;

-- ============================================================
-- Guard anti-fraud pada request_withdrawal
-- ============================================================
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
  if points_on is false then raise exception 'Points system disabled'; end if;

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
revoke execute on function public.request_withdrawal(int, text, text, text) from public, anon;
grant execute on function public.request_withdrawal(int, text, text, text) to authenticated;

-- ============================================================
-- Guard anti-spam pada send_coins (batas tx per jam)
-- ============================================================
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
  if points_on is false then raise exception 'Points system disabled'; end if;

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
revoke execute on function public.send_coins(text, uuid, int) from public, anon;
grant execute on function public.send_coins(text, uuid, int) to authenticated;

-- ============================================================
-- Guard anti-spam pada send_gift (batas tx per jam)
-- ============================================================
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
  if points_on is false then raise exception 'Points system disabled'; end if;

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
revoke execute on function public.send_gift(text, uuid, text) from public, anon;
grant execute on function public.send_gift(text, uuid, text) to authenticated;
