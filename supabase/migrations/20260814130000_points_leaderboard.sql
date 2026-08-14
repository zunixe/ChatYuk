-- ============================================================
-- ChatYuk Points: E — Leaderboard
-- RPC points_leaderboard(scope, limit): peringkat user + posisi diri.
-- scope 'weekly'  → total poin didapat 7 hari terakhir (dari point_events)
-- scope 'alltime' → saldo poin sekarang (profiles.points)
-- Hanya expose data non-sensitif: nickname, avatar, country, points.
-- User invisible/admin-hidden dikecualikan.
-- ============================================================

create index if not exists idx_point_events_weekly
  on public.point_events (created_at, user_id) where amount > 0;

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
    -- Peringkat berdasarkan saldo poin sekarang
    with ranked as (
      select
        p.id,
        p.nickname,
        p.avatar,
        p.country,
        p.points as score,
        p.is_registered,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible'
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result
    from ranked where rank <= lim;

    with ranked as (
      select p.id, p.points as score,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible'
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = auth.uid();
  else
    -- Weekly: jumlah poin DIDAPAT dalam 7 hari terakhir (amount > 0)
    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days'
        and e.amount > 0
      group by e.user_id
    ), ranked as (
      select
        p.id,
        p.nickname,
        p.avatar,
        p.country,
        en.score,
        p.is_registered,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible'
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result
    from ranked where rank <= lim;

    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days'
        and e.amount > 0
      group by e.user_id
    ), ranked as (
      select p.id, en.score,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible'
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
