-- ============================================================
-- "Top Aktif" — leaderboard keaktifan (SKOR).
--
-- LATAR: leaderboard yang ada (`points_leaderboard`) berbasis POIN. User
--   ingin leaderboard berbasis KEAKTIFAN di menu Online, dengan angka
--   sebagai SKOR (bukan "pesan") yang dihitung dari kontribusi user:
--   bikin timeline post + bikin story + chat private + chat global room.
--
-- SUMBER DATA (dicek live): posts (22/7hari), stories (3/7hari),
--   private_messages (5523/7hari), messages room (kecil).
--   `profiles.login_streak`/`last_login_date` TIDAK dipakai (cuma 3 baris
--   terisi — fitur daily-login sudah mati) → tidak reliabel.
--
-- SKOR (per user):
--   score = jumlah posts + jumlah stories + pesan private + pesan room
--   scope 'weekly'  = 7 hari terakhir
--   scope 'alltime' = seumur hidup
--   (reaksi TIDAK dihitung — sesuai permintaan; hanya konten + chat)
--
-- OUTPUT per entri: rank, uid, nickname, avatar, country, is_registered,
--   score, post_count, story_count, msg_private, msg_room.
--
-- KONSISTENSI: mengecualikan dummy + excluded uid. Hanya user "nyata"
--   (registered, atau status <> offline) — sama `points_leaderboard`.
--
-- Bukan FROZEN. Apply via Management API: 1 create + 2 grant (1 statement
-- masing-masing).
-- ============================================================

create or replace function public.activity_leaderboard(
  p_scope text default 'weekly',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  me jsonb;
  v_excl uuid[];
  v_dummy uuid[];
  v_lim int;
  v_off int;
  v_since timestamptz;
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
    -- Timeline post dibuat user.
    select p.author_id as uid, count(*)::int as posts, 0::int as stories, 0::int as priv, 0::int as room
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    -- Story dibuat user.
    select s.author_id, 0, count(*)::int, 0, 0
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    -- Pesan private dikirim user.
    select m.sender_id, 0, 0, count(*)::int, 0
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    -- Pesan room (global) dikirim user.
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
      a.posts, a.stories, a.priv, a.room, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
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
      'msg_room', f.room
    ) order by f.rank), '[]'::jsonb)
    into result
    from final f
   where f.rank > v_off and f.rank <= v_off + v_lim;

  -- Peringkat user pemanggil (lintas halaman).
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
  )
  select jsonb_build_object('rank', f.rank, 'score', f.score)
    into me
    from final f
   where f.id = auth.uid();

  return jsonb_build_object('scope', p_scope, 'entries', result, 'me', me);
end;
$function$;

revoke execute on function public.activity_leaderboard(text, integer, integer) from public, anon;
grant execute on function public.activity_leaderboard(text, integer, integer) to authenticated, service_role;

-- Verifikasi setelah apply:
--   select jsonb_pretty(public.activity_leaderboard('weekly', 10, 0));
