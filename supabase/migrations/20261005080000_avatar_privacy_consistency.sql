-- ============================================================
-- Fix konsistensi avatar: leaderboard, social_list, friend_requests,
-- my_subscriptions — selaraskan dengan avatar_for/presence_for.
--
-- LATAR (audit avatar 2026-*):
--   Beberapa RPC mengembalikan `p.avatar` MENTAH tanpa gating privasi,
--   sehingga (a) foto user ber-privat profile_photo_visibility bocor, dan
--   (b) admin (privacy_bypass_enabled) tidak diperlakukan khusus karena
--   jalur inline tidak memanggil public.privacy_can_view().
--   get_online_users diperbaiki terpisah (20261005070000).
--
--   Fungsi yang diperbaiki DI SINI:
--     - points_leaderboard(text,int,int)         → avatar entry + 'me'
--     - social_list(text,uuid,int)               → followers/following/
--                                                  friends/subscribers
--     - friend_request_inbox() / _outbox()       → avatar pengaju
--     - my_subscriptions()                       → avatar creator
--
-- FIX: ganti `p.avatar` → `case when public.privacy_can_view(p.id,
-- 'profile_photo', <viewer>) then p.avatar else '' end`.
-- privacy_can_view sudah menangani privasi user biasa + bypass admin
-- (lihat 20260924230000_admin_privacy_bypass.sql) → admin tetap melihat.
--
-- Signature TIDAK berubah; grant dipertahankan (authenticated/service_role).
-- Bukan fungsi FROZEN.
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

-- ── 1) points_leaderboard ──────────────────────────────────────────────────
create or replace function public.points_leaderboard(
  scope text default 'weekly',
  row_limit int default 50,
  row_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
  me jsonb;
  lim int;
  off int;
  v_me uuid := auth.uid();
begin
  lim := least(greatest(coalesce(row_limit, 50), 1), 100);
  off := greatest(coalesce(row_offset, 0), 0);

  if scope = 'alltime' then
    with ranked as (
      select
        p.id, p.nickname,
        case when public.privacy_can_view(p.id, 'profile_photo', v_me)
             then p.avatar else '' end as avatar,
        p.country, p.points as score, p.is_registered,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank > off and rank <= off + lim;

    with ranked as (
      select p.id, p.points as score,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = v_me;
  else
    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select
        p.id, p.nickname,
        case when public.privacy_can_view(p.id, 'profile_photo', v_me)
             then p.avatar else '' end as avatar,
        p.country, en.score, p.is_registered,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank > off and rank <= off + lim;

    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select p.id, en.score,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = v_me;
  end if;

  return jsonb_build_object(
    'scope', case when scope = 'alltime' then 'alltime' else 'weekly' end,
    'entries', coalesce(result, '[]'::jsonb),
    'me', coalesce(me, 'null'::jsonb)
  );
end;
$$;
revoke execute on function public.points_leaderboard(text, int, int) from public, anon;
grant execute on function public.points_leaderboard(text, int, int) to authenticated, service_role;

-- ── 2) social_list ─────────────────────────────────────────────────────────
create or replace function public.social_list(p_kind text, p_user uuid, p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  res jsonb;
  target uuid := coalesce(p_user, auth.uid());
  v_me uuid := auth.uid();
  lim int := greatest(1, least(p_limit, 200));
begin
  if p_kind = 'followers' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.follower_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, f.created_at
      from follows f join profiles p on p.id = f.follower_id
      where f.followee_id = target limit lim
    ) x;
  elsif p_kind = 'following' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.followee_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, f.created_at
      from follows f join profiles p on p.id = f.followee_id
      where f.follower_id = target limit lim
    ) x;
  elsif p_kind = 'friends' then
    select coalesce(jsonb_agg(x order by x.nickname), '[]'::jsonb) into res
    from (
      select p.id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered
      from follows a join follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join profiles p on p.id = a.followee_id
      where a.follower_id = target and p.id <> target
      limit lim
    ) x;
  elsif p_kind = 'subscribers' then
    select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
    from (
      select s.subscriber_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, s.expires_at
      from subscriptions s join profiles p on p.id = s.subscriber_id
      where s.creator_id = target and s.expires_at > now()
      limit lim
    ) x;
  else
    raise exception 'Invalid kind';
  end if;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.social_list(text, uuid, int) from public, anon;
grant execute on function public.social_list(text, uuid, int) to authenticated;

-- ── 3) friend_request_inbox ────────────────────────────────────────────────
create or replace function public.friend_request_inbox()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.from_id as uid, p.nickname,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end as avatar,
           p.gender, p.is_registered, fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.from_id
    where fr.to_id = me and fr.status = 'pending'
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.friend_request_inbox() from public, anon;
grant execute on function public.friend_request_inbox() to authenticated;

-- ── 4) friend_request_outbox ───────────────────────────────────────────────
create or replace function public.friend_request_outbox()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.to_id as uid, p.nickname,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end as avatar,
           p.gender, p.is_registered, fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.to_id
    where fr.from_id = me
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.friend_request_outbox() from public, anon;
grant execute on function public.friend_request_outbox() to authenticated;

-- ── 5) my_subscriptions ────────────────────────────────────────────────────
create or replace function public.my_subscriptions()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
  from (
    select s.creator_id as uid, p.nickname,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end as avatar,
           p.gender, p.is_registered, s.price, s.expires_at
    from subscriptions s join profiles p on p.id = s.creator_id
    where s.subscriber_id = me and s.expires_at > now()
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $$;
revoke execute on function public.my_subscriptions() from public, anon;
grant execute on function public.my_subscriptions() to authenticated;
