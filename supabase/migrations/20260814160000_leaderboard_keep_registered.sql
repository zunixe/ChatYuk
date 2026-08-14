-- ============================================================
-- ChatYuk Points: Leaderboard — exclude anonymous yang logout
-- Aturan tampil di leaderboard:
--   - invisible (admin) → SELALU dikecualikan
--   - anonymous (is_registered=false) + offline (logout) → dikecualikan
--   - registered (email) → SELALU masuk walau offline (poin aman)
--   - online/idle → masuk
-- ============================================================

create or replace function public.points_leaderboard(
  scope text default 'weekly',
  row_limit int default 50
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
begin
  lim := least(greatest(coalesce(row_limit, 50), 1), 100);

  if scope = 'alltime' then
    with ranked as (
      select
        p.id, p.nickname, p.avatar, p.country, p.points as score, p.is_registered,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank <= lim;

    with ranked as (
      select p.id, p.points as score,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = auth.uid();
  else
    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select
        p.id, p.nickname, p.avatar, p.country, en.score, p.is_registered,
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
    into result from ranked where rank <= lim;

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
    into me from ranked where id = auth.uid();
  end if;

  return jsonb_build_object(
    'scope', case when scope = 'alltime' then 'alltime' else 'weekly' end,
    'entries', coalesce(result, '[]'::jsonb),
    'me', coalesce(me, 'null'::jsonb)
  );
end;
$$;
revoke execute on function public.points_leaderboard(text, int) from public, anon;
grant execute on function public.points_leaderboard(text, int) to authenticated, service_role;
