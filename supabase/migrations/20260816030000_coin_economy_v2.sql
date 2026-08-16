-- ============================================================
-- ChatYuk Coin Economy v2 — "Bonus = tiket ngobrol, Paid = uang"
--
-- Tujuan:
--   1. Tutup celah keamanan yang bisa membuat platform rugi:
--      - S0: one_time_bonus menerima nominal dari client → nominal
--            dipindah ke app_settings (client tidak bisa meledakkan saldo).
--      - S1: regresi di points_admin_dev_bypass.sql — RPC room balik ke
--            `update profiles set points ± N` (bukan ledger) → income owner
--            tanpa bucket, bisa bercampur earned. Dikembalikan ke ledger.
--      - S2: send_gift tidak cek is_registered → anon bisa gift. Ditutup.
--   2. Dual pricing: fitur berbayar boleh dibayar koin belian (murah) atau
--      koin bonus (3×). Lineage ketat: paid → earned, bonus → bonus.
--   3. Ramping faucet bonus (retensi terjaga, inflasi terkendali).
--   4. Share-click reward diganti reward referral-install.
--
-- Aturan potong (server, otomatis):
--   paid  = harga murah (topup + earned)
--   bonus = bonus_price_multiplier × paid (hanya dari bucket bonus)
--   jika paid cukup → potong paid (tier 'paid'), else jika bonus cukup
--   → potong bonus (tier 'bonus'), else error 'Not enough points'.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Kolom konfigurasi di app_settings
-- ──────────────────────────────────────────────
alter table public.app_settings
  add column if not exists bonus_online_5min   int not null default 5,
  add column if not exists bonus_online_30min  int not null default 5,
  add column if not exists bonus_online_60min  int not null default 5,
  add column if not exists bonus_online_120min int not null default 5,
  add column if not exists bonus_invited       int not null default 30,
  add column if not exists bonus_first_room    int not null default 5,
  add column if not exists bonus_referral      int not null default 50,
  add column if not exists bonus_price_multiplier int not null default 3,
  add column if not exists room_create_paid    int not null default 100,
  add column if not exists room_create_pw_paid int not null default 150,
  add column if not exists room_join_paid      int not null default 5,
  add column if not exists room_extend_paid    int not null default 50,
  add column if not exists room_reads_daily_limit  int not null default 3,
  add column if not exists new_chats_daily_limit   int not null default 2,
  add column if not exists subscribe_cut_pct   int not null default 30,
  add column if not exists subscription_duration_days int not null default 30;

-- ──────────────────────────────────────────────
-- 2. Referral install (ganti share-click)
-- ──────────────────────────────────────────────
alter table public.profiles
  add column if not exists referred_by uuid references public.profiles(id);

create table if not exists public.referral_rewards (
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (referred_id)
);
create index if not exists idx_referral_rewards_referrer
  on public.referral_rewards(referrer_id, created_at);

alter table public.referral_rewards enable row level security;
drop policy if exists referral_rewards_select_own on public.referral_rewards;
create policy referral_rewards_select_own on public.referral_rewards
  for select using (referrer_id = auth.uid() or referred_id = auth.uid());

-- RPC: user baru mengklaim reward untuk pengundangnya (sekali per referred).
create or replace function public.claim_referral_reward()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  referrer uuid; reward int; points_on boolean; tot int;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select points_enabled, bonus_referral into points_on, reward
    from app_settings where id = 'global';

  select referred_by into referrer from profiles where id = me;
  if referrer is null or referrer = me then
    return jsonb_build_object('rewarded', false, 'reason', 'no_referrer');
  end if;

  if points_on is false then
    return jsonb_build_object('rewarded', false, 'reason', 'points_off');
  end if;

  insert into referral_rewards (referrer_id, referred_id) values (referrer, me)
    on conflict (referred_id) do nothing;
  if not found then
    return jsonb_build_object('rewarded', false, 'reason', 'already_rewarded');
  end if;

  tot := public.ledger_credit(referrer, 'bonus', 'referral_install', reward,
           me::text, jsonb_build_object('referred', me));
  insert into point_events (user_id, event, amount, metadata)
    values (referrer, 'referral_install', reward, jsonb_build_object('referred', me));

  return jsonb_build_object('rewarded', true, 'reward', reward);
end; $$;
revoke execute on function public.claim_referral_reward() from public, anon;
grant execute on function public.claim_referral_reward() to authenticated, service_role;

-- RPC: user baru mengikat dirinya ke referrer (dipanggil sekali setelah
-- register). Validasi: referrer harus ada, bukan diri sendiri, dan
-- referred_by belum pernah di-set. Aman dari self-referral & spam.
create or replace function public.bind_referrer(p_referrer uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_referrer is null or p_referrer = me then
    return jsonb_build_object('ok', false, 'reason', 'invalid_referrer');
  end if;
  if not exists (select 1 from profiles where id = p_referrer) then
    return jsonb_build_object('ok', false, 'reason', 'referrer_not_found');
  end if;

  select referred_by into cur from profiles where id = me;
  if cur is not null then
    return jsonb_build_object('ok', false, 'reason', 'already_bound');
  end if;

  update profiles set referred_by = p_referrer where id = me;
  return jsonb_build_object('ok', true);
end; $$;
revoke execute on function public.bind_referrer(uuid) from public, anon;
grant execute on function public.bind_referrer(uuid) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 3. Helper ledger: potong topup → earned (paid)
-- ──────────────────────────────────────────────
create or replace function public.ledger_spend_paid(
  p_user uuid, p_type text, p_amount int, p_ref text default null
) returns int language plpgsql security definer set search_path = public as $$
declare t int; e int; need int; take int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;
  select coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into t, e from coin_ledger where user_id = p_user;
  if (t + e) < p_amount then raise exception 'Not enough paid'; end if;

  need := p_amount;
  take := least(t, need);
  if take > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'topup',p_type,-take,p_ref);
    need := need - take;
  end if;
  if need > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'earned',p_type,-need,p_ref);
  end if;
  return public.wallet_sync_points(p_user);
end; $$;
revoke execute on function public.ledger_spend_paid(uuid, text, int, text) from public, anon;
grant execute on function public.ledger_spend_paid(uuid, text, int, text) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 4. Helper ledger: dual pricing → {tier, remaining}
-- ──────────────────────────────────────────────
create or replace function public.ledger_spend_dual(
  p_user uuid, p_type text, p_paid int, p_bonus int, p_ref text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare b int; t int; e int; remaining int;
begin
  if p_paid <= 0 and p_bonus <= 0 then
    return jsonb_build_object('tier', 'paid', 'remaining', public.wallet_sync_points(p_user));
  end if;

  -- Coba tier berbayar dulu.
  select coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into t, e from coin_ledger where user_id = p_user;
  if (t + e) >= p_paid then
    remaining := public.ledger_spend_paid(p_user, p_type, p_paid, p_ref);
    return jsonb_build_object('tier', 'paid', 'remaining', remaining);
  end if;

  -- Fallback tier bonus.
  select coalesce(sum(amount) filter (where bucket='bonus'),0) into b
    from coin_ledger where user_id = p_user;
  if b >= p_bonus then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'bonus',p_type,-p_bonus,p_ref);
    remaining := public.wallet_sync_points(p_user);
    return jsonb_build_object('tier', 'bonus', 'remaining', remaining);
  end if;

  raise exception 'Not enough points';
end; $$;
revoke execute on function public.ledger_spend_dual(uuid, text, int, int, text) from public, anon;
grant execute on function public.ledger_spend_dual(uuid, text, int, int, text) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 5. streak_bonus_amount → ramping 10..40
-- ──────────────────────────────────────────────
create or replace function public.streak_bonus_amount(streak int)
returns int language sql immutable as $$
  select case streak
    when 1 then 10 when 2 then 12 when 3 then 15 when 4 then 18
    when 5 then 20 when 6 then 25 else 40 end;
$$;

-- ──────────────────────────────────────────────
-- 6. daily_login_bonus → ledger-based (fix regresi S1)
-- ──────────────────────────────────────────────
create or replace function public.daily_login_bonus()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  today date; last_date date; cur_streak int; new_streak int; bonus int;
  cur_points int; points_on boolean; tot int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into cur_points from profiles where id = auth.uid();
    return jsonb_build_object('points', coalesce(cur_points,0), 'streak', 0, 'bonus', 0);
  end if;

  today := (now() at time zone 'Asia/Jakarta')::date;
  select last_login_date, login_streak, points
    into last_date, cur_streak, cur_points
    from profiles where id = auth.uid();

  if last_date is not null and last_date >= today then
    return jsonb_build_object('points', coalesce(cur_points,0),
      'streak', coalesce(cur_streak,0), 'bonus', 0);
  end if;

  if last_date is not null and last_date = today - 1 then
    new_streak := coalesce(cur_streak,0) + 1;
    if new_streak > 7 then new_streak := 1; end if;
  else
    new_streak := 1;
  end if;
  bonus := public.streak_bonus_amount(new_streak);

  update profiles set
    login_streak = new_streak,
    last_login_date = today,
    login_at = now(),
    room_reads_today = 0,
    new_chats_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min']
  where id = auth.uid();

  tot := public.ledger_credit(auth.uid(), 'bonus', 'daily_login', bonus,
           null, jsonb_build_object('streak', new_streak));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'daily_login', bonus, jsonb_build_object('streak', new_streak));

  return jsonb_build_object('points', tot, 'streak', new_streak, 'bonus', bonus);
end; $$;
revoke execute on function public.daily_login_bonus() from public, anon;
grant execute on function public.daily_login_bonus() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 7. one_time_bonus → nominal dari server (fix S0)
-- ──────────────────────────────────────────────
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int language plpgsql security definer set search_path = public as $$
declare
  valid_actions text[]; nominal int; tot int; points_on boolean;
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

  -- Nominal dibaca dari server, bukan dari client (anti-farming).
  select
    case action_key
      when 'registered'        then bonus_registered
      when 'rated_app'         then bonus_rated
      when 'completed_profile' then bonus_profile
      when 'shared_app'        then bonus_shared
      when 'invited_friend'    then bonus_invited
      when 'first_photo'       then bonus_first_photo
      when 'first_room_chat'   then bonus_first_room
      when 'online_5min'       then bonus_online_5min
      when 'online_30min'      then bonus_online_30min
      when 'online_60min'      then bonus_online_60min
      when 'online_120min'     then bonus_online_120min
      else 0
    end
  into nominal from app_settings where id = 'global';

  if exists (select 1 from profiles where id = auth.uid()
             and one_time_actions->>action_key = 'true') then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
    where id = auth.uid();

  tot := public.ledger_credit(auth.uid(), 'bonus', 'one_time', nominal,
           null, jsonb_build_object('action', action_key));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'bonus', nominal, jsonb_build_object('action', action_key));

  return tot;
end; $$;
grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 8. register_bonus → nominal server
-- ──────────────────────────────────────────────
create or replace function public.register_bonus()
returns int language plpgsql security definer set search_path = public as $$
begin
  return public.one_time_bonus('registered', 0);
end; $$;
grant execute on function public.register_bonus() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 9. room_read_bonus → limit 3/hari (nominal bonus_room_read)
-- ──────────────────────────────────────────────
create or replace function public.room_read_bonus()
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; ok boolean; tot int; rr int; lim int;
begin
  select points_enabled, bonus_room_read, room_reads_daily_limit
    into points_on, rr, lim from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  update profiles set room_reads_today = room_reads_today + 1
    where id = auth.uid() and room_reads_today < lim;
  ok := found;
  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'room_read', rr);
    insert into point_events (user_id, event, amount) values (auth.uid(), 'room_read', rr);
    return tot;
  end if;
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.room_read_bonus() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 10. new_chat_bonus → limit 2/hari
-- ──────────────────────────────────────────────
create or replace function public.new_chat_bonus(other_uid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; tot int; ok boolean; nc int; lim int;
begin
  select points_enabled, bonus_new_chat, new_chats_daily_limit
    into points_on, nc, lim from app_settings where id = 'global';
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
    where id = auth.uid() and new_chats_today < lim;
  ok := found;
  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'new_chat', nc,
             null, jsonb_build_object('other_uid', other_uid));
    insert into point_events (user_id, event, amount, metadata)
      values (auth.uid(), 'new_chat', nc, jsonb_build_object('other_uid', other_uid));
    return tot;
  end if;
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.new_chat_bonus(uuid) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 11. send_coins → paid-only (topup+earned), penerima earned
-- ──────────────────────────────────────────────
create or replace function public.send_coins(
  p_chat_id text, p_receiver_id uuid, p_amount int
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

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

  -- Hanya koin belian (topup+earned) — koin bonus TIDAK bisa ditransfer.
  remaining := public.ledger_spend_paid(uid, 'coin_sent', p_amount, p_chat_id);

  -- Penerima selalu dapat 'earned' (bisa dicairkan setelah KYC).
  perform public.ledger_credit(p_receiver_id, 'earned', 'coin_received', p_amount,
    p_chat_id, jsonb_build_object('from', uid));

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', p_amount);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0));
end; $$;
revoke execute on function public.send_coins(text, uuid, int) from public, anon;
grant execute on function public.send_coins(text, uuid, int) to authenticated;

-- ──────────────────────────────────────────────
-- 12. send_gift → dual + guard registered (fix S2)
--     paid tier: cut 30%, penerima earned.
--     bonus tier: tanpa cut, penerima bonus.
-- ──────────────────────────────────────────────
create or replace function public.send_gift(
  p_chat_id text, p_receiver_id uuid, p_gift_id text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int; mult int;
  my_name text; my_gender text; am_registered boolean;
  n int; bonus_price int; cut int; net int;
  tier text; remaining int; recv_bucket text; recv_amount int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;

  select points_enabled, coalesce(gift_cut_pct,30), coalesce(bonus_price_multiplier,3)
    into points_on, cut_pct, mult from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;

  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;
  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  bonus_price := n * mult;
  tier := (public.ledger_spend_dual(uid, 'gift_sent', n, bonus_price, p_chat_id))->>'tier';
  remaining := public.wallet_sync_points(uid);

  if tier = 'paid' then
    cut := (n * cut_pct) / 100;
    net := n - cut;
    recv_bucket := 'earned';
    recv_amount := net;
    if cut > 0 then
      insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
        values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
                jsonb_build_object('gift', p_gift_id, 'gross', n, 'net', net, 'pct', cut_pct));
    end if;
  else
    net := n;
    cut := 0;
    recv_bucket := 'bonus';
    recv_amount := bonus_price;
  end if;

  if recv_amount > 0 then
    perform public.ledger_credit(p_receiver_id, recv_bucket, 'gift_recv', recv_amount,
      p_chat_id, jsonb_build_object('gift', p_gift_id, 'from', uid, 'tier', tier));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -case when tier = 'paid' then n else bonus_price end,
            jsonb_build_object('gift', p_gift_id, 'tier', tier)),
           (p_receiver_id, 'gift_recv', recv_amount,
            jsonb_build_object('gift', p_gift_id, 'tier', tier));

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut, 'tier', tier);
end; $$;
revoke execute on function public.send_gift(text, uuid, text) from public, anon;
grant execute on function public.send_gift(text, uuid, text) to authenticated;

-- ──────────────────────────────────────────────
-- 13. Room RPC → dual + lineage (fix regresi S1)
-- ──────────────────────────────────────────────
create or replace function public.create_private_room(
  p_name text, p_icon text, p_country text, p_password text default null
) returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  uid uuid := auth.uid(); points_on boolean;
  has_pw boolean := (p_password is not null and length(p_password) > 0);
  active_count int; new_id text; my_name text;
  paid int; create_paid int; create_pw_paid int; bonus_p int; mult int;
  remaining int; r jsonb;
  is_admin boolean := ((auth.jwt() ->> 'email') = 'zunixe@gmail.com');
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then raise exception 'Invalid room name'; end if;
  if p_country is null or p_country = '' then raise exception 'Invalid country'; end if;

  if not is_admin then
    select count(*) into active_count from public.rooms
     where owner_id = uid and is_private = true
       and (expires_at is null or expires_at > now());
    if active_count >= 2 then raise exception 'Room limit reached'; end if;
  end if;

  select points_enabled, room_create_paid, room_create_pw_paid, bonus_price_multiplier
    into points_on, create_paid, create_pw_paid, mult from app_settings where id = 'global';
  paid := case when has_pw then create_pw_paid else create_paid end;
  bonus_p := paid * mult;

  if points_on is not false and not is_admin then
    r := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'create');
    remaining := (r->>'remaining')::int;
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

  insert into public.room_members (room_id, user_id) values (new_id, uid) on conflict do nothing;
  return jsonb_build_object('id', new_id, 'points', coalesce(remaining, 0));
end; $$;
revoke execute on function public.create_private_room(text, text, text, text) from public, anon;
grant execute on function public.create_private_room(text, text, text, text) to authenticated;

create or replace function public.join_private_room(
  p_room_id text, p_password text default null
) returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  uid uuid := auth.uid(); r record; points_on boolean;
  am_registered boolean; remaining int; charged int := 0;
  paid int; bonus_p int; mult int; tier text; res jsonb;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.is_private and r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired'; end if;

  if not r.is_private or r.owner_id = uid
     or exists (select 1 from public.room_members m
                where m.room_id = p_room_id and m.user_id = uid) then
    insert into public.room_members (room_id, user_id) values (p_room_id, uid) on conflict do nothing;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0));
  end if;

  if r.has_password then
    if p_password is null or r.password_hash is null
       or crypt(p_password, r.password_hash) <> r.password_hash then
      raise exception 'Wrong password'; end if;
  end if;

  select points_enabled, room_join_paid, bonus_price_multiplier
    into points_on, paid, mult from app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'join');
    tier := res->>'tier';
    remaining := (res->>'remaining')::int;
    charged := case when tier = 'paid' then paid else bonus_p end;

    -- fee ke owner hanya jika joiner terdaftar. Lineage: paid→earned, bonus→bonus.
    select is_registered into am_registered from public.profiles where id = uid;
    if am_registered is true and r.owner_id is not null and r.owner_id <> uid then
      perform public.ledger_credit(r.owner_id,
        case when tier = 'paid' then 'earned' else 'bonus' end,
        'private_room_income', charged, p_room_id,
        jsonb_build_object('joiner', uid, 'tier', tier));
      insert into public.point_events (user_id, event, amount)
        values (r.owner_id, 'private_room_income', charged);
    end if;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  insert into public.room_members (room_id, user_id) values (p_room_id, uid) on conflict do nothing;
  return jsonb_build_object('ok', true, 'charged', charged, 'points', coalesce(remaining, 0));
end; $$;
revoke execute on function public.join_private_room(text, text) from public, anon;
grant execute on function public.join_private_room(text, text) to authenticated;

create or replace function public.extend_private_room(p_room_id text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  uid uuid := auth.uid(); r record; points_on boolean;
  paid int; bonus_p int; mult int; remaining int; res jsonb;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;

  select points_enabled, room_extend_paid, bonus_price_multiplier
    into points_on, paid, mult from app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'extend');
    remaining := (res->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  update public.rooms
    set expires_at = greatest(coalesce(expires_at, now()), now()) + interval '7 days'
    where id = p_room_id returning expires_at into r.expires_at;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
                            'expires_at', r.expires_at);
end; $$;
revoke execute on function public.extend_private_room(text) from public, anon;
grant execute on function public.extend_private_room(text) to authenticated;

-- ──────────────────────────────────────────────
-- 14. unlock_photo → dual + lineage
-- ──────────────────────────────────────────────
create or replace function public.unlock_photo(p_photo_id uuid, p_mode text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  points_on boolean; once_cost int; perm_cost int; owner_pct int; mult int;
  cost int; bonus_p int; owner_id uuid; owner_share int; remaining int;
  tier text; res jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_mode not in ('once','perm') then raise exception 'Invalid mode'; end if;

  select points_enabled, photo_unlock_once, photo_unlock_perm, photo_unlock_owner_pct,
         bonus_price_multiplier
    into points_on, once_cost, perm_cost, owner_pct, mult
    from app_settings where id = 'global';

  if points_on is false then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  select user_id into owner_id from user_photos where id = p_photo_id;
  if owner_id is null then raise exception 'Photo not found'; end if;
  if owner_id = me then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  cost := case p_mode when 'perm' then perm_cost else once_cost end;
  bonus_p := cost * mult;

  if exists (select 1 from photo_unlocks where viewer_id = me and photo_id = p_photo_id) then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  res := public.ledger_spend_dual(me, 'photo_unlock', cost, bonus_p, p_photo_id::text);
  tier := res->>'tier';
  remaining := (res->>'remaining')::int;

  owner_share := (cost * owner_pct) / 100;
  if owner_share > 0 then
    perform public.ledger_credit(owner_id,
      case when tier = 'paid' then 'earned' else 'bonus' end,
      'photo_income', owner_share, p_photo_id::text,
      jsonb_build_object('viewer', me, 'mode', p_mode, 'tier', tier));
  end if;
  if tier = 'paid' then
    insert into platform_revenue (source, amount, metadata)
      values ('photo_unlock', cost - owner_share,
              jsonb_build_object('photo_id', p_photo_id, 'mode', p_mode, 'viewer', me, 'owner', owner_id));
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (me, 'photo_unlock', -case when tier = 'paid' then cost else bonus_p end,
            jsonb_build_object('photo_id', p_photo_id, 'mode', p_mode, 'tier', tier));

  if p_mode = 'perm' then
    insert into photo_unlocks (viewer_id, photo_id) values (me, p_photo_id)
      on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'points', remaining, 'mode', p_mode, 'tier', tier);
end; $$;
revoke execute on function public.unlock_photo(uuid, text) from public, anon;
grant execute on function public.unlock_photo(uuid, text) to authenticated;

-- ──────────────────────────────────────────────
-- 15. RPC: ambil harga room untuk UI (hapus hardcode client)
-- ──────────────────────────────────────────────
create or replace function public.room_pricing()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return (select jsonb_build_object(
    'create_paid', room_create_paid,
    'create_pw_paid', room_create_pw_paid,
    'join_paid', room_join_paid,
    'extend_paid', room_extend_paid,
    'multiplier', bonus_price_multiplier
  ) from app_settings where id = 'global');
end; $$;
revoke execute on function public.room_pricing() from public, anon;
grant execute on function public.room_pricing() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 16. admin_get/update_point_settings: sertakan kolom baru
-- ──────────────────────────────────────────────
create or replace function public.admin_get_point_settings()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  return (select jsonb_build_object(
    'photo_upload_reward', photo_upload_reward,
    'photo_unlock_once', photo_unlock_once,
    'photo_unlock_perm', photo_unlock_perm,
    'photo_unlock_owner_pct', photo_unlock_owner_pct,
    'bonus_registered', bonus_registered,
    'bonus_rated', bonus_rated,
    'bonus_shared', bonus_shared,
    'bonus_profile', bonus_profile,
    'bonus_first_photo', bonus_first_photo,
    'bonus_room_read', bonus_room_read,
    'bonus_new_chat', bonus_new_chat,
    'bonus_invited', bonus_invited,
    'bonus_first_room', bonus_first_room,
    'bonus_referral', bonus_referral,
    'bonus_online_5min', bonus_online_5min,
    'bonus_online_30min', bonus_online_30min,
    'bonus_online_60min', bonus_online_60min,
    'bonus_online_120min', bonus_online_120min,
    'bonus_price_multiplier', bonus_price_multiplier,
    'room_create_paid', room_create_paid,
    'room_create_pw_paid', room_create_pw_paid,
    'room_join_paid', room_join_paid,
    'room_extend_paid', room_extend_paid,
    'room_reads_daily_limit', room_reads_daily_limit,
    'new_chats_daily_limit', new_chats_daily_limit,
    'subscribe_cut_pct', subscribe_cut_pct,
    'subscription_duration_days', subscription_duration_days,
    'cost_chat_text', cost_chat_text,
    'cost_chat_image', cost_chat_image,
    'cost_view_once', cost_view_once,
    'share_url', share_url,
    'share_click_reward', share_click_reward,
    'share_click_cap_daily', share_click_cap_daily
  ) from app_settings where id = 'global');
end; $$;
revoke execute on function public.admin_get_point_settings() from public, anon;
grant execute on function public.admin_get_point_settings() to authenticated, service_role;

create or replace function public.admin_update_point_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    photo_upload_reward   = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once     = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm     = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct= coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    bonus_registered      = coalesce((p->>'bonus_registered')::int, bonus_registered),
    bonus_rated           = coalesce((p->>'bonus_rated')::int, bonus_rated),
    bonus_shared          = coalesce((p->>'bonus_shared')::int, bonus_shared),
    bonus_profile         = coalesce((p->>'bonus_profile')::int, bonus_profile),
    bonus_first_photo     = coalesce((p->>'bonus_first_photo')::int, bonus_first_photo),
    bonus_room_read       = coalesce((p->>'bonus_room_read')::int, bonus_room_read),
    bonus_new_chat        = coalesce((p->>'bonus_new_chat')::int, bonus_new_chat),
    bonus_invited         = coalesce((p->>'bonus_invited')::int, bonus_invited),
    bonus_first_room      = coalesce((p->>'bonus_first_room')::int, bonus_first_room),
    bonus_referral        = coalesce((p->>'bonus_referral')::int, bonus_referral),
    bonus_online_5min     = coalesce((p->>'bonus_online_5min')::int, bonus_online_5min),
    bonus_online_30min    = coalesce((p->>'bonus_online_30min')::int, bonus_online_30min),
    bonus_online_60min    = coalesce((p->>'bonus_online_60min')::int, bonus_online_60min),
    bonus_online_120min   = coalesce((p->>'bonus_online_120min')::int, bonus_online_120min),
    bonus_price_multiplier= coalesce((p->>'bonus_price_multiplier')::int, bonus_price_multiplier),
    room_create_paid      = coalesce((p->>'room_create_paid')::int, room_create_paid),
    room_create_pw_paid   = coalesce((p->>'room_create_pw_paid')::int, room_create_pw_paid),
    room_join_paid        = coalesce((p->>'room_join_paid')::int, room_join_paid),
    room_extend_paid      = coalesce((p->>'room_extend_paid')::int, room_extend_paid),
    room_reads_daily_limit= coalesce((p->>'room_reads_daily_limit')::int, room_reads_daily_limit),
    new_chats_daily_limit = coalesce((p->>'new_chats_daily_limit')::int, new_chats_daily_limit),
    subscribe_cut_pct     = coalesce((p->>'subscribe_cut_pct')::int, subscribe_cut_pct),
    subscription_duration_days = coalesce((p->>'subscription_duration_days')::int, subscription_duration_days),
    cost_chat_text        = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image       = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once        = coalesce((p->>'cost_view_once')::int, cost_view_once),
    share_url             = coalesce(p->>'share_url', share_url),
    share_click_reward    = coalesce((p->>'share_click_reward')::int, share_click_reward),
    share_click_cap_daily = coalesce((p->>'share_click_cap_daily')::int, share_click_cap_daily),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_update_point_settings(jsonb) from public, anon;
grant execute on function public.admin_update_point_settings(jsonb) to authenticated, service_role;
