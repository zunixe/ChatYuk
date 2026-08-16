-- ============================================================
-- ChatYuk Wallet FASE 3 — Gift + Platform Cut
--
-- Creator monetization: user kirim GIFT ke user lain.
--   - Pengirim bayar N coin (urutan potong bonus→topup→earned).
--   - Platform ambil CUT % dari N → masuk platform_revenue (profit kamu).
--   - Penerima terima (N - cut) dengan LINEAGE terjaga:
--       porsi pembayaran dari bonus  → penerima 'bonus'  (tak bisa cair)
--       porsi dari topup/earned      → penerima 'earned' (bisa cair)
--     Cut dibagi proporsional agar total selalu kekal (N = net + cut).
--
-- Platform cut % disimpan di app_settings.gift_cut_pct (default 30).
-- Pesan bukti gift type 'gift' (nominal & gift_id di text/metadata).
-- ============================================================

-- gift_cut_pct di app_settings
alter table public.app_settings
  add column if not exists gift_cut_pct int not null default 30;

-- ── Katalog gift ──
create table if not exists public.gift_catalog (
  id         text primary key,
  emoji      text not null,
  name_id    text not null,   -- nama Indonesia
  name_en    text not null,   -- nama English
  coins      int  not null check (coins > 0),
  sort_order int  not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.gift_catalog (id, emoji, name_id, name_en, coins, sort_order) values
  ('rose',      '🌹', 'Mawar',        'Rose',        10,   1),
  ('coffee',    '☕', 'Kopi',         'Coffee',      25,   2),
  ('teddy',     '🧸', 'Boneka',       'Teddy Bear',  50,   3),
  ('cake',      '🎂', 'Kue',          'Cake',        75,   4),
  ('diamond',   '💎', 'Berlian',      'Diamond',     150,  5),
  ('crown',     '👑', 'Mahkota',      'Crown',       300,  6),
  ('rocket',    '🚀', 'Roket',        'Rocket',      500,  7),
  ('sportscar', '🏎️', 'Mobil Sport',  'Sports Car',  1000, 8)
on conflict (id) do update set
  emoji = excluded.emoji, name_id = excluded.name_id, name_en = excluded.name_en,
  coins = excluded.coins, sort_order = excluded.sort_order, active = true;

alter table public.gift_catalog enable row level security;
drop policy if exists gift_catalog_select on public.gift_catalog;
create policy gift_catalog_select on public.gift_catalog
  for select using (active = true);
grant select on public.gift_catalog to anon, authenticated;

-- ── Log pendapatan platform (profit dari cut) — admin only ──
create table if not exists public.platform_revenue (
  id         bigint generated always as identity primary key,
  source     text not null,        -- 'gift_cut'
  amount     int  not null,        -- coin cut
  from_user  uuid,
  to_user    uuid,
  ref_id     text,                 -- chat_id / gift_id
  metadata   jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists idx_platform_revenue_created on public.platform_revenue(created_at);

alter table public.platform_revenue enable row level security;
drop policy if exists platform_revenue_admin on public.platform_revenue;
create policy platform_revenue_admin on public.platform_revenue
  for select using ((auth.jwt() ->> 'email') = 'zunixe@gmail.com');
revoke insert, update, delete on public.platform_revenue from anon, authenticated;

-- ── izinkan type 'gift' di private_messages ──
alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check
  check (type in ('text', 'image', 'view_once', 'view_once_expired', 'coin', 'gift'));

-- Trigger preview last_message: type 'gift' → '[Hadiah]'
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
      when new.type = 'gift' then '[Hadiah]'
      else new.text end,
    last_message_at = now(),
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $$ language plpgsql security definer;

-- ============================================================
-- RPC: list_gifts()
-- ============================================================
create or replace function public.list_gifts()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.sort_order), '[]'::jsonb) into res
  from (
    select id, emoji, name_id, name_en, coins, sort_order
    from gift_catalog where active = true
  ) x;
  return res;
end; $$;
grant execute on function public.list_gifts() to anon, authenticated, service_role;

-- ============================================================
-- RPC: send_gift(chat_id, receiver, gift_id)
--   - potong pengirim bonus→topup→earned
--   - platform cut % → platform_revenue
--   - net ke penerima, lineage: bonus→bonus, (topup+earned)→earned
--     cut dibagi proporsional supaya total kekal
-- ============================================================
create or replace function public.send_gift(
  p_chat_id text, p_receiver_id uuid, p_gift_id text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int;
  my_name text; my_gender text;
  b int; t int; e int; need int;
  pay_bonus int := 0; pay_topup int := 0; pay_earned int := 0;
  n int; cut int; net int;
  earn_src int;         -- porsi pembayaran yg withdrawable-eligible (topup+earned)
  recv_earned int; recv_bonus int; remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;

  select points_enabled, coalesce(gift_cut_pct,30) into points_on, cut_pct
    from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

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
  cut := (n * cut_pct) / 100;   -- floor
  net := n - cut;

  -- pembagian net ke penerima, lineage proporsional
  earn_src := pay_topup + pay_earned;
  if net <= 0 then
    recv_earned := 0; recv_bonus := 0;
  elsif earn_src = 0 then
    recv_earned := 0; recv_bonus := net;               -- semua dari bonus
  elsif pay_bonus = 0 then
    recv_earned := net; recv_bonus := 0;               -- semua withdrawable
  else
    recv_earned := (net * earn_src) / n;               -- proporsional (floor)
    recv_bonus  := net - recv_earned;                  -- sisa
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

-- ============================================================
-- RPC: admin_gift_revenue() — ringkasan profit platform (admin)
-- ============================================================
create or replace function public.admin_gift_revenue()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  select jsonb_build_object(
    'total_cut', coalesce((select sum(amount) from platform_revenue where source='gift_cut'),0),
    'today_cut', coalesce((select sum(amount) from platform_revenue
       where source='gift_cut' and created_at >= current_date at time zone 'Asia/Jakarta'),0),
    'gift_count', (select count(*) from platform_revenue where source='gift_cut'),
    'cut_pct', (select gift_cut_pct from app_settings where id='global')
  ) into res;
  return res;
end; $$;
revoke execute on function public.admin_gift_revenue() from public, anon;
grant execute on function public.admin_gift_revenue() to authenticated, service_role;
