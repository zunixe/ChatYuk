-- ============================================================
-- ChatYuk Social Graph — Follow / Friend / Subscribe
--
-- - follows: satu arah (follower → followee). Fan = pengikut.
-- - friend_requests: kirim → accept → mutual follow (= friend).
-- - subscriptions: fans bayar pakai koin belian (topup+earned) untuk
--   subscribe creator. Cut platform 30% → platform_revenue, sisanya
--   'earned' ke creator. Bonus TIDAK berlaku untuk subscribe.
-- - Counter denormalized di profiles (followers_count, following_count,
--   subscriber_count) + trigger agar list cepat.
-- ============================================================

-- ── Kolom sosial di profiles ──
alter table public.profiles
  add column if not exists followers_count  int not null default 0,
  add column if not exists following_count  int not null default 0,
  add column if not exists subscriber_count int not null default 0,
  add column if not exists subscription_price int not null default 0;

-- ── follows ──
create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists idx_follows_followee on public.follows(followee_id, created_at);

alter table public.follows enable row level security;
drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows for select using (true);
drop policy if exists follows_insert_own on public.follows;
create policy follows_insert_own on public.follows for insert with check (auth.uid() = follower_id);
drop policy if exists follows_delete_own on public.follows;
create policy follows_delete_own on public.follows for delete using (auth.uid() = follower_id);

-- ── friend_requests ──
create table if not exists public.friend_requests (
  id           bigint generated always as identity primary key,
  from_id      uuid not null references public.profiles(id) on delete cascade,
  to_id        uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending','accepted','rejected')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (from_id <> to_id)
);
create unique index if not exists uq_friend_request_pending
  on public.friend_requests(from_id, to_id) where status = 'pending';
create index if not exists idx_friend_requests_to on public.friend_requests(to_id, status);

alter table public.friend_requests enable row level security;
drop policy if exists friend_requests_select on public.friend_requests;
create policy friend_requests_select on public.friend_requests
  for select using (from_id = auth.uid() or to_id = auth.uid());
drop policy if exists friend_requests_insert_own on public.friend_requests;
create policy friend_requests_insert_own on public.friend_requests
  for insert with check (auth.uid() = from_id);
drop policy if exists friend_requests_update_own on public.friend_requests;
create policy friend_requests_update_own on public.friend_requests
  for update using (to_id = auth.uid());

-- ── subscriptions ──
create table if not exists public.subscriptions (
  subscriber_id uuid not null references public.profiles(id) on delete cascade,
  creator_id    uuid not null references public.profiles(id) on delete cascade,
  price         int  not null check (price > 0),
  starts_at     timestamptz not null default now(),
  expires_at    timestamptz not null,
  primary key (subscriber_id, creator_id),
  check (subscriber_id <> creator_id)
);
create index if not exists idx_subscriptions_creator on public.subscriptions(creator_id, expires_at);

alter table public.subscriptions enable row level security;
drop policy if exists subscriptions_select on public.subscriptions;
create policy subscriptions_select on public.subscriptions for select using (true);
drop policy if exists subscriptions_insert_own on public.subscriptions;
create policy subscriptions_insert_own on public.subscriptions
  for insert with check (auth.uid() = subscriber_id);
drop policy if exists subscriptions_update_own on public.subscriptions;
create policy subscriptions_update_own on public.subscriptions
  for update using (auth.uid() = subscriber_id);

-- ── Trigger counter follows ──
create or replace function public.follow_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update profiles set followers_count = followers_count + 1 where id = new.followee_id;
    update profiles set following_count = following_count + 1 where id = new.follower_id;
    return new;
  elsif tg_op = 'DELETE' then
    update profiles set followers_count = greatest(followers_count - 1, 0) where id = old.followee_id;
    update profiles set following_count = greatest(following_count - 1, 0) where id = old.follower_id;
    return old;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists follow_count_trigger on public.follows;
create trigger follow_count_trigger after insert or delete on public.follows
  for each row execute function public.follow_count_sync();

-- ── Trigger counter subscriptions ──
create or replace function public.subscriber_count_sync() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update profiles set subscriber_count = subscriber_count + 1 where id = new.creator_id;
    return new;
  elsif tg_op = 'DELETE' then
    update profiles set subscriber_count = greatest(subscriber_count - 1, 0) where id = old.creator_id;
    return old;
  end if;
  return null;
end; $$ language plpgsql security definer;

drop trigger if exists subscriber_count_trigger on public.subscriptions;
create trigger subscriber_count_trigger after insert or delete on public.subscriptions
  for each row execute function public.subscriber_count_sync();

-- ── Helper push notif ──
create or replace function public.social_push(p_to uuid, p_title text, p_body text, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare t text;
begin
  select fcm_token into t from profiles where id = p_to;
  if t is not null and t <> '' then
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('token', t, 'title', p_title, 'body', p_body, 'data', p_data)
      );
    exception when others then null;
    end;
  end if;
end; $$;

-- ── RPC: follow / unfollow ──
create or replace function public.follow_user(p_followee uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); nm text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_followee is null or p_followee = me then raise exception 'Invalid target'; end if;
  if not exists (select 1 from profiles where id = p_followee) then
    raise exception 'User not found';
  end if;
  insert into follows (follower_id, followee_id) values (me, p_followee)
    on conflict do nothing;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_followee, coalesce(nm, 'Anon'), 'started following you',
    jsonb_build_object('type', 'follow', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'following', true);
end; $$;
revoke execute on function public.follow_user(uuid) from public, anon;
grant execute on function public.follow_user(uuid) to authenticated;

create or replace function public.unfollow_user(p_followee uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  delete from follows where follower_id = me and followee_id = p_followee;
  return jsonb_build_object('ok', true, 'following', false);
end; $$;
revoke execute on function public.unfollow_user(uuid) from public, anon;
grant execute on function public.unfollow_user(uuid) to authenticated;

-- ── RPC: friend request ──
create or replace function public.send_friend_request(p_to uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); nm text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_to is null or p_to = me then raise exception 'Invalid target'; end if;
  if not exists (select 1 from profiles where id = p_to) then
    raise exception 'User not found';
  end if;
  if exists (select 1 from follows where follower_id = me and followee_id = p_to
             and exists (select 1 from follows where follower_id = p_to and followee_id = me)) then
    return jsonb_build_object('ok', true, 'already_friends', true);
  end if;

  insert into friend_requests (from_id, to_id) values (me, p_to)
    on conflict do nothing;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_to, coalesce(nm, 'Anon'), 'sent you a friend request',
    jsonb_build_object('type', 'friend_request', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'status', 'pending');
end; $$;
revoke execute on function public.send_friend_request(uuid) from public, anon;
grant execute on function public.send_friend_request(uuid) to authenticated;

create or replace function public.respond_friend_request(p_request_id bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); req record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into req from friend_requests where id = p_request_id and to_id = me;
  if not found then raise exception 'Request not found'; end if;
  if req.status <> 'pending' then raise exception 'Already responded'; end if;

  update friend_requests set status = case when p_accept then 'accepted' else 'rejected' end,
    responded_at = now() where id = p_request_id;

  if p_accept then
    insert into follows (follower_id, followee_id) values (req.from_id, req.to_id)
      on conflict do nothing;
    insert into follows (follower_id, followee_id) values (req.to_id, req.from_id)
      on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'accepted', p_accept);
end; $$;
revoke execute on function public.respond_friend_request(bigint, boolean) from public, anon;
grant execute on function public.respond_friend_request(bigint, boolean) to authenticated;

-- ── RPC: subscribe (paid-only) ──
create or replace function public.subscribe_creator(p_creator uuid, p_periods int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); price int; cut_pct int; duration_days int; periods int;
  points_on boolean; am_registered boolean; remaining int; cost int; cut int; net int;
  expire timestamptz;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_creator is null or p_creator = me then raise exception 'Invalid creator'; end if;

  select is_registered into am_registered from profiles where id = me;
  if am_registered is not true then raise exception 'Subscriber must be registered'; end if;

  select subscription_price into price from profiles where id = p_creator;
  if price is null or price <= 0 then raise exception 'Not a paid creator'; end if;

  select points_enabled, subscribe_cut_pct, subscription_duration_days
    into points_on, cut_pct, duration_days from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  periods := greatest(coalesce(p_periods, 1), 1);
  if periods > 12 then raise exception 'Invalid periods'; end if;

  cost := price * periods;
  cut := (cost * cut_pct) / 100;
  net := cost - cut;

  -- Paid-only: hanya topup+earned (bonus tidak berlaku).
  remaining := public.ledger_spend_paid(me, 'subscribe', cost, p_creator::text);

  -- Perpanjang / buat subscription.
  select expires_at into expire from subscriptions
    where subscriber_id = me and creator_id = p_creator;
  if expire is null or expire < now() then
    expire := now();
  end if;
  expire := expire + make_interval(days => duration_days * periods);

  insert into subscriptions (subscriber_id, creator_id, price, starts_at, expires_at)
    values (me, p_creator, price, now(), expire)
    on conflict (subscriber_id, creator_id)
    do update set price = excluded.price, expires_at = excluded.expires_at;

  if net > 0 then
    perform public.ledger_credit(p_creator, 'earned', 'subscribe_income', net,
      me::text, jsonb_build_object('subscriber', me, 'periods', periods));
  end if;
  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('subscribe_cut', cut, me, p_creator, p_creator::text,
              jsonb_build_object('gross', cost, 'net', net, 'pct', cut_pct, 'periods', periods));
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (me, 'subscribe', -cost, jsonb_build_object('creator', p_creator, 'periods', periods));

  return jsonb_build_object('ok', true, 'points', remaining, 'expires_at', expire,
    'net', net, 'cut', cut);
end; $$;
revoke execute on function public.subscribe_creator(uuid, int) from public, anon;
grant execute on function public.subscribe_creator(uuid, int) to authenticated;

create or replace function public.unsubscribe_creator(p_creator uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  delete from subscriptions where subscriber_id = me and creator_id = p_creator;
  return jsonb_build_object('ok', true);
end; $$;
revoke execute on function public.unsubscribe_creator(uuid) from public, anon;
grant execute on function public.unsubscribe_creator(uuid) to authenticated;

-- ── RPC: set harga subscribe (creator) ──
create or replace function public.set_subscription_price(p_price int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); am_registered boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select is_registered into am_registered from profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;
  if p_price < 0 or p_price > 100000 then raise exception 'Invalid price'; end if;
  update profiles set subscription_price = p_price where id = me;
  return jsonb_build_object('ok', true, 'price', p_price);
end; $$;
revoke execute on function public.set_subscription_price(int) from public, anon;
grant execute on function public.set_subscription_price(int) to authenticated;

-- ── RPC: status sosial diri sendiri (untuk UI) ──
create or replace function public.my_social_status(p_other uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  return jsonb_build_object(
    'following', exists(select 1 from follows where follower_id = me and followee_id = p_other),
    'follows_me', exists(select 1 from follows where follower_id = p_other and followee_id = me),
    'friend', exists(select 1 from follows a join follows b
      on a.follower_id = b.followee_id and a.followee_id = b.follower_id
      where a.follower_id = me and a.followee_id = p_other),
    'friend_request_sent', exists(select 1 from friend_requests
      where from_id = me and to_id = p_other and status = 'pending'),
    'friend_request_received', exists(select 1 from friend_requests
      where from_id = p_other and to_id = me and status = 'pending'),
    'subscribed', exists(select 1 from subscriptions
      where subscriber_id = me and creator_id = p_other and expires_at > now()),
    'is_subscribed_to_me', exists(select 1 from subscriptions
      where subscriber_id = p_other and creator_id = me and expires_at > now())
  );
end; $$;
revoke execute on function public.my_social_status(uuid) from public, anon;
grant execute on function public.my_social_status(uuid) to authenticated;

-- ── RPC: list (followers / following / friends / subscribers) ──
create or replace function public.social_list(p_kind text, p_user uuid, p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; target uuid := coalesce(p_user, auth.uid());
begin
  if p_kind = 'followers' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.follower_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
             f.created_at
      from follows f join profiles p on p.id = f.follower_id
      where f.followee_id = target limit greatest(1, least(p_limit, 200))
    ) x;
  elsif p_kind = 'following' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.followee_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
             f.created_at
      from follows f join profiles p on p.id = f.followee_id
      where f.follower_id = target limit greatest(1, least(p_limit, 200))
    ) x;
  elsif p_kind = 'friends' then
    select coalesce(jsonb_agg(x order by x.nickname), '[]'::jsonb) into res
    from (
      select p.id as uid, p.nickname, p.avatar, p.gender, p.is_registered
      from follows a join follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join profiles p on p.id = a.followee_id
      where a.follower_id = target and p.id <> target
      limit greatest(1, least(p_limit, 200))
    ) x;
  elsif p_kind = 'subscribers' then
    select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
    from (
      select s.subscriber_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
             s.expires_at
      from subscriptions s join profiles p on p.id = s.subscriber_id
      where s.creator_id = target and s.expires_at > now()
      limit greatest(1, least(p_limit, 200))
    ) x;
  else
    raise exception 'Invalid kind';
  end if;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.social_list(text, uuid, int) from public, anon;
grant execute on function public.social_list(text, uuid, int) to authenticated;

-- ── RPC: friend request inbox / outbox ──
create or replace function public.friend_request_inbox()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.from_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.from_id
    where fr.to_id = me and fr.status = 'pending'
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.friend_request_inbox() from public, anon;
grant execute on function public.friend_request_inbox() to authenticated;

create or replace function public.friend_request_outbox()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.to_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.to_id
    where fr.from_id = me
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.friend_request_outbox() from public, anon;
grant execute on function public.friend_request_outbox() to authenticated;

-- ── RPC: my subscriptions (creator yang saya follow berbayar) ──
create or replace function public.my_subscriptions()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
  from (
    select s.creator_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           s.price, s.expires_at
    from subscriptions s join profiles p on p.id = s.creator_id
    where s.subscriber_id = me and s.expires_at > now()
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.my_subscriptions() from public, anon;
grant execute on function public.my_subscriptions() to authenticated;
