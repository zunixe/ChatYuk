-- ============================================================
-- Guard sosial: akun anon tidak boleh follow/teman.
--
-- Latar: tab Pengikut/Mengikuti/Teman menampilkan anon (follow_user
-- security definer bypass RLS follows_insert_own yang sudah benar).
-- Data lama sudah dibersihkan manual (follows + friend_requests).
--
-- Guard: penelepon & target WAJIB is_registered. Bypass: dummy
-- (admin_dummy_uids) & admin — sesuai pola _anon_write_ok.
-- ============================================================

-- follow_user: tambahkan cek di awal (definisi lain identik live).
create or replace function public.follow_user(p_followee uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid(); nm text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_followee is null or p_followee = me then raise exception 'Invalid target'; end if;
  if not exists (select 1 from profiles where id = p_followee) then
    raise exception 'User not found';
  end if;
  -- Guard sosial anon (bypass: dummy & admin).
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  if exists (select 1 from profiles where id = me and is_registered = false)
     or exists (select 1 from profiles where id = p_followee and is_registered = false) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
  end if;
  insert into follows (follower_id, followee_id) values (me, p_followee)
    on conflict do nothing;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_followee, coalesce(nm, 'Anon'), 'started following you',
    jsonb_build_object('type', 'follow', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'following', true);
end;
$fn$;

-- unfollow_user: hanya caller harus registered (target bebas — berhenti
-- follow selalu aman, mencegah orphan).
create or replace function public.unfollow_user(p_followee uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_followee is null then raise exception 'Invalid target'; end if;
  delete from follows where follower_id = me and followee_id = p_followee;
  return jsonb_build_object('ok', true, 'following', false);
end;
$fn$;

-- send_friend_request (signature live: p_to uuid): caller & target registered.
create or replace function public.send_friend_request(p_to uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid(); nm text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_to is null or p_to = me then raise exception 'Invalid target'; end if;
  if not exists (select 1 from profiles where id = p_to) then
    raise exception 'User not found';
  end if;
  -- Guard sosial anon (bypass: dummy & admin).
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  if exists (select 1 from profiles where id = me and is_registered = false)
     or exists (select 1 from profiles where id = p_to and is_registered = false) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
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
end;
$fn$;

-- respond_friend_request (signature live: p_request_id bigint, p_accept
-- boolean): responder registered; pasangan juga dicek via trigger.
create or replace function public.respond_friend_request(p_request_id bigint, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid(); req record; friend_count int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Guard sosial anon (bypass: dummy & admin) — sebelum apa pun.
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
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

    -- Bonus first-friend untuk KEDUA belah pihak (sekali seumur hidup).
    select friends_count into friend_count from public.profiles where id = req.from_id;
    if coalesce(friend_count, 0) <= 1 then
      perform public.one_time_bonus('first_friend', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'accepted', p_accept);
end;
$fn$;

-- Trigger lapis kedua: walau RPC lupa guard / insert langsung, RLS +
-- trigger menolak follows lintas anon.
create or replace function public._social_registered_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if exists (
    select 1 from public.profiles p
    where p.id in (new.follower_id, new.followee_id)
      and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
  end if;
  return new;
end;
$fn$;

drop trigger if exists social_guard_follows on public.follows;
create trigger social_guard_follows
before insert or update on public.follows
for each row execute function public._social_registered_guard();

drop trigger if exists social_guard_friend_requests on public.friend_requests;
create trigger social_guard_friend_requests
before insert or update on public.friend_requests
for each row execute function public._social_registered_guard();
