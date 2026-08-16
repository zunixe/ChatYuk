-- ============================================================
-- ChatYuk Wallet FASE 1 — Ledger + Wallet Dua/Tiga-Saldo
--
-- Tujuan: ubah `profiles.points` tunggal → sistem wallet berbasis
-- coin_ledger (append-only) dengan 3 bucket:
--   bonus  = hasil bonus sistem (signup/login/misi) → TIDAK bisa cair
--   topup  = beli sendiri (Fase 2)                   → belanja saja, tak cair sendiri
--   earned = terima gift/transfer ber-lineage uang   → BISA cair (Fase 5, setelah KYC)
--
-- Aturan potong SEMUA pengeluaran: bonus → topup → earned
-- Aturan transfer (send_coins) — lineage terbawa:
--   porsi dari bonus  → penerima bucket 'bonus'
--   porsi dari topup  → penerima bucket 'earned'
--   porsi dari earned → penerima bucket 'earned'
--
-- Keamanan: coin_ledger append-only (tolak UPDATE/DELETE), tulis hanya
-- lewat RPC security definer. profiles.points dikunci immutable dari client.
-- profiles.points dipertahankan sebagai CACHE (di-sync dari ledger) untuk
-- kompat UI & leaderboard lama. point_events TETAP ditulis (quests/leaderboard).
-- ============================================================

-- ── Pastikan kolom pendukung ada (idempoten, apa pun kondisi remote) ──
alter table public.profiles
  add column if not exists points int not null default 50,
  add column if not exists one_time_actions jsonb not null default '{}',
  add column if not exists room_reads_today int not null default 0,
  add column if not exists new_chats_today int not null default 0,
  add column if not exists login_streak int not null default 0,
  add column if not exists last_login_date date;

alter table public.app_settings
  add column if not exists points_enabled boolean not null default true;

-- streak bonus helper (idempoten)
create or replace function public.streak_bonus_amount(streak int)
returns int language sql immutable as $$
  select case streak
    when 1 then 25 when 2 then 30 when 3 then 35 when 4 then 40
    when 5 then 45 when 6 then 50 else 100 end;
$$;

-- ============================================================
-- 1. Tabel coin_ledger (append-only, sumber kebenaran saldo)
-- ============================================================
create table if not exists public.coin_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  bucket     text not null check (bucket in ('bonus','topup','earned')),
  type       text not null,
  amount     int  not null check (amount <> 0),
  ref_id     text,
  metadata   jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists idx_coin_ledger_user on public.coin_ledger(user_id, created_at);
create index if not exists idx_coin_ledger_bucket on public.coin_ledger(user_id, bucket);

alter table public.coin_ledger enable row level security;

-- SELECT hanya baris sendiri (admin bypass)
drop policy if exists coin_ledger_select_own on public.coin_ledger;
create policy coin_ledger_select_own on public.coin_ledger
  for select using (
    auth.uid() = user_id
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );

-- INSERT/UPDATE/DELETE langsung dari client DITOLAK (tak ada policy write).
-- Penulisan hanya lewat RPC security definer (owner postgres bypass RLS).
revoke insert, update, delete on public.coin_ledger from anon, authenticated;
grant select on public.coin_ledger to authenticated;

-- Append-only: tolak UPDATE & DELETE walau dari mana pun (kecuali superuser)
create or replace function public.coin_ledger_no_mutate()
returns trigger language plpgsql as $$
begin
  raise exception 'coin_ledger is append-only';
end; $$;
drop trigger if exists coin_ledger_no_update on public.coin_ledger;
create trigger coin_ledger_no_update before update on public.coin_ledger
  for each row execute function public.coin_ledger_no_mutate();
drop trigger if exists coin_ledger_no_delete on public.coin_ledger;
create trigger coin_ledger_no_delete before delete on public.coin_ledger
  for each row execute function public.coin_ledger_no_mutate();

-- ============================================================
-- 2. View wallet_balances (3 bucket + total)
-- ============================================================
create or replace view public.wallet_balances as
  select user_id,
    coalesce(sum(amount) filter (where bucket='bonus'), 0)  as bonus_balance,
    coalesce(sum(amount) filter (where bucket='topup'), 0)  as topup_balance,
    coalesce(sum(amount) filter (where bucket='earned'), 0) as earned_balance,
    coalesce(sum(amount), 0) as total_balance
  from public.coin_ledger
  group by user_id;

-- ============================================================
-- 3. Helper: sinkron cache profiles.points dari ledger
-- ============================================================
create or replace function public.wallet_sync_points(p_user uuid)
returns int language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  select coalesce(sum(amount), 0) into tot from coin_ledger where user_id = p_user;
  update profiles set points = tot where id = p_user;
  return tot;
end; $$;

-- ============================================================
-- 4. Helper internal: ledger_credit (tambah coin ke bucket)
-- ============================================================
create or replace function public.ledger_credit(
  p_user uuid, p_bucket text, p_type text, p_amount int,
  p_ref text default null, p_meta jsonb default '{}'
) returns int language plpgsql security definer set search_path = public as $$
begin
  if p_amount <= 0 then
    return public.wallet_sync_points(p_user);
  end if;
  insert into coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
    values (p_user, p_bucket, p_type, p_amount, p_ref, coalesce(p_meta,'{}'::jsonb));
  return public.wallet_sync_points(p_user);
end; $$;

-- ============================================================
-- 5. Helper: ledger_spend (potong bonus→topup→earned)
--    Return: total saldo baru. Raise 'Not enough points' bila kurang.
-- ============================================================
create or replace function public.ledger_spend(
  p_user uuid, p_type text, p_amount int, p_ref text default null
) returns int language plpgsql security definer set search_path = public as $$
declare
  b int; t int; e int; need int := p_amount; take int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;

  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = p_user;

  if (b + t + e) < p_amount then
    raise exception 'Not enough points';
  end if;

  -- bonus dulu
  take := least(b, need);
  if take > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'bonus',p_type,-take,p_ref);
    need := need - take;
  end if;
  -- topup
  if need > 0 then
    take := least(t, need);
    if take > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (p_user,'topup',p_type,-take,p_ref);
      need := need - take;
    end if;
  end if;
  -- earned
  if need > 0 then
    take := least(e, need);
    if take > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (p_user,'earned',p_type,-take,p_ref);
      need := need - take;
    end if;
  end if;

  return public.wallet_sync_points(p_user);
end; $$;

-- ============================================================
-- 6. Migrasi saldo lama profiles.points → coin_ledger bucket 'bonus'
--    Idempoten: hanya sekali per user (ditandai metadata reason=migrate_v1)
-- ============================================================
insert into public.coin_ledger (user_id, bucket, type, amount, metadata)
select p.id, 'bonus', 'migrate', p.points,
       jsonb_build_object('reason','migrate_v1')
from public.profiles p
where p.points > 0
  and not exists (
    select 1 from public.coin_ledger l
    where l.user_id = p.id and l.metadata->>'reason' = 'migrate_v1'
  );

-- Sinkron cache untuk semua user yang punya ledger (samakan points = total)
update public.profiles pr
set points = w.total_balance
from public.wallet_balances w
where w.user_id = pr.id;

-- ============================================================
-- 7. Kunci celah RLS: points TIDAK bisa diubah client langsung.
--    (RPC security definer / owner postgres tetap bisa — bypass RLS.)
-- ============================================================
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id)
  with check (
    auth.uid() = id
    and status in ('online', 'idle', 'offline')
    and length(trim(nickname)) >= 3
    and length(nickname) <= 20
    -- points immutable: NEW.points harus sama dengan nilai tersimpan
    and points = (select p.points from public.profiles p where p.id = auth.uid())
  );

-- ============================================================
-- 8. RPC klien baru: get_wallet, get_ledger_history
-- ============================================================
create or replace function public.get_wallet()
returns jsonb language plpgsql security definer set search_path = public as $$
declare b int; t int; e int;
begin
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = auth.uid();
  return jsonb_build_object(
    'bonus', b, 'topup', t, 'earned', e,
    'total', b + t + e,
    'withdrawable', e
  );
end; $$;
revoke execute on function public.get_wallet() from public, anon;
grant execute on function public.get_wallet() to authenticated, service_role;

create or replace function public.get_ledger_history(row_limit int default 200)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select id, bucket, type, amount, ref_id, metadata, created_at
    from coin_ledger where user_id = auth.uid()
    order by created_at desc limit greatest(1, least(row_limit, 500))
  ) x;
  return res;
end; $$;
revoke execute on function public.get_ledger_history(int) from public, anon;
grant execute on function public.get_ledger_history(int) to authenticated, service_role;

-- ============================================================
-- 9. REFACTOR RPC lama → tulis ke ledger (bonus bucket) + tetap point_events
--    Semua mempertahankan guard points_enabled (freeze).
-- ============================================================

-- ── daily_login_bonus (jsonb, streak) → bonus bucket ──
drop function if exists public.daily_login_bonus();
create function public.daily_login_bonus()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  today date; last_date date; cur_streak int; new_streak int; bonus int;
  cur_points int; points_on boolean; tot int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
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

  -- reset counter harian + streak, TANPA mengubah points (points via ledger)
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

-- ── deduct_chat_point → ledger_spend ──
create or replace function public.deduct_chat_point(msg_type text)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; cost int; remaining int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
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
grant execute on function public.deduct_chat_point(text) to authenticated, service_role;

-- ── room_read_bonus → bonus bucket (limit 5/hari) ──
create or replace function public.room_read_bonus()
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; ok boolean; tot int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
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
grant execute on function public.room_read_bonus() to authenticated, service_role;

-- ── one_time_bonus → bonus bucket ──
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int language plpgsql security definer set search_path = public as $$
declare valid_actions text[]; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
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
grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;

-- ── new_chat_bonus → bonus bucket (limit 3/hari, sekali per pasangan) ──
create or replace function public.new_chat_bonus(other_uid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; tot int; ok boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
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
grant execute on function public.new_chat_bonus(uuid) to authenticated, service_role;

-- ── claim_weekly_quest → bonus bucket (+50) ──
create or replace function public.claim_weekly_quest(quest_key text, tz_offset_minutes int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare wk_start timestamptz; wk text; progress int; target int; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
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
revoke execute on function public.claim_weekly_quest(text, int) from public, anon;
grant execute on function public.claim_weekly_quest(text, int) to authenticated, service_role;

-- ============================================================
-- 10. Private rooms → ledger_spend. Income owner room = bucket 'bonus'
--     (mekanik in-app, BUKAN jalur cash-out; cash-out riil hanya via gift Fase 3
--      dengan lineage. Ini cegah pencucian bonus→room→earned.)
-- ============================================================
create or replace function public.create_private_room(
  p_name text, p_icon text, p_country text, p_password text default null
) returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  uid uuid := auth.uid(); points_on boolean; cost int;
  has_pw boolean := (p_password is not null and length(p_password) > 0);
  active_count int; new_id text; my_name text; remaining int;
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

  select points_enabled into points_on from public.app_settings where id = 'global';
  cost := case when has_pw then 150 else 100 end;

  if points_on is not false and not is_admin then
    remaining := public.ledger_spend(uid, 'spend_room', cost, 'create');
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

  select points_enabled into points_on from public.app_settings where id = 'global';

  if points_on is not false then
    remaining := public.ledger_spend(uid, 'spend_room', 5, 'join');
    charged := 5;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_join', -5);

    -- fee ke owner HANYA jika joiner terdaftar → bucket 'bonus' (bukan cash-out)
    select is_registered into am_registered from public.profiles where id = uid;
    if am_registered is true and r.owner_id is not null and r.owner_id <> uid then
      perform public.ledger_credit(r.owner_id, 'bonus', 'private_room_income', 5, p_room_id);
      insert into public.point_events (user_id, event, amount)
        values (r.owner_id, 'private_room_income', 5);
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
declare uid uuid := auth.uid(); r record; points_on boolean; remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;

  select points_enabled into points_on from public.app_settings where id = 'global';
  if points_on is not false then
    remaining := public.ledger_spend(uid, 'spend_room', 50, 'extend');
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_extend', -50);
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

-- ============================================================
-- 11. send_coins → transfer dengan LINEAGE bucket
--     pengirim potong bonus→topup→earned; penerima:
--       bonus  → bonus   (tak bisa cair)
--       topup  → earned  (bisa cair)
--       earned → earned  (bisa cair)
-- ============================================================
create or replace function public.send_coins(
  p_chat_id text, p_receiver_id uuid, p_amount int
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean;
  b int; t int; e int; need int; take_bonus int := 0; take_topup int := 0; take_earned int := 0;
  recv_earned int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

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
-- 12. Admin mass bonus / reset → lewat ledger juga (konsisten)
-- ============================================================
create or replace function public.admin_mass_bonus(bonus int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare affected int := 0; u uuid;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  for u in select id from profiles where is_registered = true loop
    perform public.ledger_credit(u, 'bonus', 'admin_mass_bonus', bonus);
    affected := affected + 1;
  end loop;
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_mass_bonus', bonus, jsonb_build_object('affected_users', affected));
  return jsonb_build_object('affected', affected, 'bonus', bonus);
end; $$;
revoke execute on function public.admin_mass_bonus(int) from public, anon;
grant execute on function public.admin_mass_bonus(int) to authenticated, service_role;

-- admin_reset_points: set semua user ke 50 bonus (bersihkan ledger → 1 baris bonus 50)
create or replace function public.admin_reset_points()
returns int language plpgsql security definer set search_path = public as $$
declare affected int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  -- hapus semua ledger via truncate tidak bisa (append-only trigger blok DELETE).
  -- Sebagai gantinya: catat penyesuaian agar total tiap user = 50 bonus.
  insert into coin_ledger (user_id, bucket, type, amount, metadata)
  select w.user_id, 'bonus', 'admin_adjust', (50 - w.total_balance),
         jsonb_build_object('reason','admin_reset')
  from wallet_balances w
  where (50 - w.total_balance) <> 0;
  get diagnostics affected = row_count;

  update profiles pr set points = w.total_balance
    from wallet_balances w where w.user_id = pr.id;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_reset_all', 0, jsonb_build_object('affected_users', affected));
  return affected;
end; $$;
revoke execute on function public.admin_reset_points() from public, anon;
grant execute on function public.admin_reset_points() to authenticated, service_role;
