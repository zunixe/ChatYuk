-- Teman = saling follow (satu sumber kebenaran: tabel follows).
--
-- Latar (analisa DB live 2026-10-26): daftar Teman, my_social_status,
-- privacy_can_view, Top Aktif sudah memakai saling follow
-- (`_privacy_are_friends`), tapi story memakai `_are_friends` =
-- friend_requests accepted. Akibatnya 23 pasangan yang request-nya accepted
-- tapi sudah tidak saling follow masih saling melihat story "friends"
-- padahal UI menyatakan mereka bukan teman.
--
-- Perubahan:
--   1. `_are_friends` = saling follow (sama dengan `_privacy_are_friends`).
--      Semua pemakai story (policy stories_select, story_slides, story_tray,
--      mark_story_seen*, toggle_story_like) ikut lewat fungsi ini — tidak
--      ada fungsi FROZEN yang disentuh.
--   2. Kolom aditif `friend_requests.auto_follow`: true bila follow pengirim
--      dibuat OLEH request (bukan follow yang sudah ada sebelumnya).
--   3. `send_friend_request` = follow + ajakan follow balik. Kalau target
--      sudah follow saya → langsung teman (request ditandai accepted).
--   4. `follow_user`: follow yang membuat saling follow menandai request
--      pending antara keduanya accepted, mengembalikan `friend: true`.
--   5. Tolak / batalkan request hanya menghapus follow buatan request
--      (`auto_follow`), follow lama tidak tersentuh.
--   `unfollow_user` & `respond_friend_request(accept)` tidak berubah perilaku.
--
-- SAFE: kolom baru aditif (default false) di friend_requests; hanya mengganti
--       body _are_friends, send_friend_request, follow_user,
--       respond_friend_request, cancel_friend_request (bukan FROZEN). Kontrak
--       arg & tipe return sama; follow_user menambah key `friend`.
--       Fitur terdampak: tombol Ikuti/Tambah Teman (profil, leaderboard,
--       online, daftar chat, chat 1:1), inbox permintaan teman, visibilitas
--       story "friends". Tidak menyentuh RLS/policy/grant.

alter table public.friend_requests
  add column if not exists auto_follow boolean not null default false;

create or replace function public._are_friends(a uuid, b uuid)
returns boolean
language sql
stable
set search_path to 'public'
as $function$
  select exists (
    select 1
    from public.follows f1
    join public.follows f2
      on f1.followee_id = f2.follower_id
     and f1.follower_id = f2.followee_id
    where f1.follower_id = a
      and f1.followee_id = b
  )
$function$;

create or replace function public.follow_user(p_followee uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid(); nm text; v_friend boolean;
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

  -- Follow balik = teman: tutup permintaan pending di antara keduanya.
  v_friend := exists (select 1 from follows
                       where follower_id = p_followee and followee_id = me);
  if v_friend then
    update friend_requests
       set status = 'accepted', responded_at = now()
     where status = 'pending'
       and ((from_id = me and to_id = p_followee)
         or (from_id = p_followee and to_id = me));
  end if;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_followee, coalesce(nm, 'Anon'), 'started following you',
    jsonb_build_object('type', 'follow', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'following', true, 'friend', v_friend);
end;
$function$;

create or replace function public.send_friend_request(p_to uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid(); nm text; v_was_following boolean;
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
  if public._are_friends(me, p_to) then
    return jsonb_build_object('ok', true, 'already_friends', true);
  end if;

  -- Tambah Teman = ikuti + ajak follow balik.
  v_was_following := exists (select 1 from follows
                              where follower_id = me and followee_id = p_to);
  insert into follows (follower_id, followee_id) values (me, p_to)
    on conflict do nothing;

  -- Target sudah mengikuti saya → kini saling follow = teman.
  if exists (select 1 from follows where follower_id = p_to and followee_id = me) then
    update friend_requests
       set status = 'accepted', responded_at = now()
     where status = 'pending'
       and ((from_id = me and to_id = p_to) or (from_id = p_to and to_id = me));
    return jsonb_build_object('ok', true, 'already_friends', true);
  end if;

  insert into friend_requests (from_id, to_id, auto_follow)
  values (me, p_to, not v_was_following)
  on conflict do nothing;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_to, coalesce(nm, 'Anon'), 'sent you a friend request',
    jsonb_build_object('type', 'friend_request', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'status', 'pending');
end;
$function$;

create or replace function public.respond_friend_request(p_request_id bigint, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  elsif req.auto_follow then
    -- Ditolak: buang follow yang dibuat oleh request ini saja.
    delete from follows where follower_id = req.from_id and followee_id = req.to_id;
  end if;

  return jsonb_build_object('ok', true, 'accepted', p_accept);
end;
$function$;

create or replace function public.cancel_friend_request(p_request_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  req record;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select * into req
    from public.friend_requests
   where id = p_request_id and from_id = me;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- Hanya request PENDING yang bisa dibatalkan. Bila sudah direspons,
  -- biarkan (histori tetap) — bukan hak pengirim membatalkannya.
  if req.status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'not_pending',
                              'status', req.status);
  end if;

  delete from public.friend_requests where id = p_request_id;
  -- Follow yang dibuat oleh request ini ikut ditarik.
  if req.auto_follow then
    delete from public.follows where follower_id = me and followee_id = req.to_id;
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;
