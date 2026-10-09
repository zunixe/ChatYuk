-- ============================================================
-- Top Aktif: sertakan followers_count & friends_count per entry
-- (dipakai baris 'X Pengikut · Y Teman' di sheet Top Aktif, seperti
-- kartu menu Online).
-- ============================================================

CREATE OR REPLACE FUNCTION public.activity_leaderboard(p_scope text DEFAULT 'weekly'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  me jsonb;
  v_excl uuid[];
  v_dummy uuid[];
  v_lim int;
  v_off int;
  v_since timestamptz;
  v_me uuid := auth.uid();
begin
  v_lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_off := greatest(coalesce(p_offset, 0), 0);
  v_since := case when p_scope = 'alltime' then null
                  else (now() - interval '7 days') end;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  with raw as (
    select p.author_id as uid, count(*)::int as posts, 0::int as stories, 0::int as priv, 0::int as room
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    select s.author_id, 0, count(*)::int, 0, 0
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    select m.sender_id, 0, 0, count(*)::int, 0
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, 0, 0, 0, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
  ),
  agg as (
    select uid,
           sum(posts)::int as posts,
           sum(stories)::int as stories,
           sum(priv)::int as priv,
           sum(room)::int as room,
           (sum(posts) + sum(stories) + sum(priv) + sum(room))::int as score
      from raw
     group by uid
  ),
  final as (
    select
      p.id, p.nickname, p.avatar, p.country, p.is_registered, p.gender,
      p.followers_count, p.friends_count,
      a.posts, a.stories, a.priv, a.room, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
      -- Hormati privasi Top Aktif (nobody/friends/only/kecuali).
      and public.privacy_can_view(p.id, 'leaderboard', v_me)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', f.rank,
      'uid', f.id,
      'nickname', f.nickname,
      'avatar', f.avatar,
      'country', f.country,
      'gender', f.gender,
      'is_registered', f.is_registered,
      'score', f.score,
      'post_count', f.posts,
      'story_count', f.stories,
      'msg_private', f.priv,
      'msg_room', f.room,
      'followers_count', coalesce(f.followers_count,0),
      'friends_count', coalesce(f.friends_count,0)
    ) order by f.rank), '[]'::jsonb)
    into result
    from final f
   where f.rank > v_off and f.rank <= v_off + v_lim;

  with raw as (
    select p.author_id as uid, count(*)::int s
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    select s.author_id, count(*)::int
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    select m.sender_id, count(*)::int
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
  ),
  agg as ( select uid, sum(s)::int as score from raw group by uid ),
  final as (
    select p.id, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
      and public.privacy_can_view(p.id, 'leaderboard', v_me)
  )
  select jsonb_build_object('rank', f.rank, 'score', f.score)
    into me
    from final f
   where f.id = v_me;

  return jsonb_build_object('scope', p_scope, 'entries', result, 'me', me);
end;
$function$
