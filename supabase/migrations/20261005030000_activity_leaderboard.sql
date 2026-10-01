-- ============================================================
-- "Top Aktif" — leaderboard keaktifan (pesan + reaksi).
--
-- LATAR: leaderboard yang ada (`points_leaderboard`) berbasis POIN. User
--   ingin leaderboard berbasis KEAKTIFAN: siapa yang paling banyak
--   berinteraksi (kirim pesan & reaksi), diakses dari menu Online.
--
-- SUMBER DATA (dicek live): `private_messages` (7528 baris, 5523/7 hari),
--   `messages` room (kecil), `message_reactions` (jarang tapi tumbuh).
--   `profiles.login_streak`/`last_login_date` TIDAK dipakai (cuma 3 baris
--   terisi — fitur daily-login sudah mati) → tidak reliabel.
--
-- SKOR (per user):
--   score = jumlah pesan private + jumlah pesan room + jumlah reaksi
--   scope 'weekly'  = 7 hari terakhir
--   scope 'alltime' = seumur hidup
--
-- KONSISTENSI: mengecualikan dummy + excluded uid. Hanya menampilkan user
--   "nyata" (registered, atau status <> offline) — sama seperti
--   `points_leaderboard`. Entri boleh dilihat semua user (read-only).
--
-- Bukan FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md):
--   1 create function + 2 grant. Butuh 1 statement per request.
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
    -- Pesan private dikirim user.
    select m.sender_id as uid,
           count(*)::int as msg_private,
           0::int as msg_room,
           0::int as reactions
      from public.private_messages m
     where m.sender_id is not null
       and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    -- Pesan room dikirim user.
    select m.sender_id,
           0,
           count(*)::int,
           0
      from public.messages m
     where m.sender_id is not null
       and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    -- Reaksi yang user berikan.
    select r.user_id,
           0,
           0,
           count(*)::int
      from public.message_reactions r
     where r.user_id is not null
       and (v_since is null or r.created_at >= v_since)
     group by r.user_id
  ),
  agg as (
    select uid,
           sum(msg_private)::int as msg_private,
           sum(msg_room)::int as msg_room,
           sum(reactions)::int as reactions,
           (sum(msg_private) + sum(msg_room) + sum(reactions))::int as score
      from raw
     group by uid
  ),
  final as (
    select
      p.id, p.nickname, p.avatar, p.country, p.is_registered,
      a.msg_private, a.msg_room, a.reactions, a.score,
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
      'is_registered', f.is_registered,
      'score', f.score,
      'msg_count', f.msg_private + f.msg_room,
      'reaction_count', f.reactions
    ) order by f.rank), '[]'::jsonb)
    into result
    from final f
   where f.rank > v_off and f.rank <= v_off + v_lim;

  -- Peringkat user pemanggil (lintas halaman).
  with raw as (
    select m.sender_id as uid, count(*)::int s, 0::int r
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, 0, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select r.user_id, 0, count(*)::int
      from public.message_reactions r
     where r.user_id is not null and (v_since is null or r.created_at >= v_since)
     group by r.user_id
  ),
  agg as (
    select uid, (sum(s) + sum(r))::int as score from raw group by uid
  ),
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
