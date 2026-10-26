-- ============================================================
-- FIX: GHOST MODE (invisible berbayar) TIDAK BERFUNGSI SAMA SEKALI.
--
-- TEMUAN AUDIT (2026-10-26):
--   Fitur "Ghost Mode" dijual ke user (`buy_ghost_mode_v2`, YukCoin harian)
--   dengan janji di UI: "Sembunyikan status online-mu. Kamu tetap bisa chat."
--   (lib/config/strings_points_mx.dart: ghostModeDesc).
--
--   TAPI `public.ghost_mode_active` hanya dibaca oleh:
--     * buy_ghost_mode_v2()  — saat membeli
--     * is_ghost_mode()      — cek status milik sendiri
--   NOL referensi di seluruh query presence:
--     * get_online_users  → 0
--     * presence_for      → 0
--     * admin_stats*      → 0
--
--   Akibatnya user MEMBAYAR koin tapi tetap muncul di daftar Online dengan
--   status aslinya. Fitur berbayar tanpa efek + admin tak bisa melihat siapa
--   yang sedang ghost (tidak ada jejak di panel).
--
-- PERBAIKAN (3 bagian):
--   1) get_online_users  : user ghost DIKELUARKAN dari kandidat.
--   2) presence_for      : status user ghost dipaksa 'offline' bagi viewer
--                          lain (tetap bisa chat — yang disembunyikan hanya
--                          presence, sesuai janji fitur). `last_seen` tetap
--                          mengikuti last_seen_visibility (tidak diubah).
--   3) RPC admin baru `admin_ghost_users` supaya panel admin bisa MENAMPILKAN
--      siapa yang sedang ghost (jawaban atas "kenapa di admin tidak tercatat").
--
-- TIDAK mengubah privacy_can_view, semantik ghost milik admin
-- (`app_settings.invisible_admin_uid`), atau tabel apa pun.
--
-- Catatan definisi "ghost aktif": `expires_at > now()`.
--
-- CARA APPLY: Management API / SQL editor (CLI db push HANG di Mac ini).
-- ROLLBACK: re-apply `20261006090000_get_online_users_perf.sql` dan
--           `20261020150000_fix_presence_for_invisible_uid.sql`.
-- ============================================================

-- ── 1) get_online_users: keluarkan user ghost ──────────────────────────────
-- Isi fungsi identik dengan 20261006090000_get_online_users_perf.sql, HANYA
-- menambah satu klausa `not exists (ghost_mode_active)` di CTE candidates.
create or replace function public.get_online_users(
  p_country text DEFAULT NULL::text,
  p_limit integer DEFAULT 100
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  rows jsonb;
  v_me uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
  v_bypass boolean;
begin
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;

  v_bypass :=
    coalesce(
      (select privacy_bypass_enabled from public.app_settings where id = 'global'),
      false
    )
    and coalesce(auth.email(), '') = 'zunixe@gmail.com';

  with candidates as (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen, p.about,
      coalesce(p.presence_visibility, 'nobody')      as presence_vis,
      coalesce(p.last_seen_visibility, 'nobody')     as seen_vis,
      coalesce(p.profile_photo_visibility, 'nobody') as photo_vis,
      coalesce(p.about_visibility, 'nobody')         as about_vis
    from public.profiles p
    where p.id <> v_me
      and p.status in ('online', 'idle')
      and p.last_seen >= now() - interval '30 minutes'
      and (p_country is null or p.country = p_country)
      -- GHOST MODE: user yang membayar invisible TIDAK boleh muncul.
      -- Admin bypass tetap melihat (untuk keperluan audit/monitoring).
      and (v_bypass or not exists (
        select 1 from public.ghost_mode_active g
        where g.user_id = p.id and g.expires_at > now()
      ))
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_me)
      )
    order by p.last_seen desc
    limit p_limit
  ),
  chat_partners as (
    select distinct c2.uid
    from public.private_chats c
    cross join lateral unnest(c.participants) as c2(uid)
    where c.participants @> array[v_me]::uuid[]
  ),
  room_mates as (
    select distinct b.user_id as uid
    from public.room_members a
    join public.room_members b on b.room_id = a.room_id
    where a.user_id = v_me
  ),
  excl as (
    select e.owner_id, e.field
    from public.profile_privacy_exclusions e
    where e.excluded_uid = v_me
  ),
  friends as (
    select f1.followee_id as uid
    from public.follows f1
    join public.follows f2
      on f1.followee_id = f2.follower_id
     and f1.follower_id = f2.followee_id
    where f1.follower_id = v_me
  ),
  resolved as (
    select
      s.*,
      (v_bypass
        or s.id in (select uid from friends))            as is_friend,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'presence')      as excl_presence,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'last_seen')     as excl_seen,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'profile_photo') as excl_photo,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'about')         as excl_about,
      (s.id in (select uid from chat_partners)
        or s.id in (select uid from room_mates))         as photo_partner
    from candidates s
  ),
  flags as (
    select
      r.*,
      (v_bypass or r.presence_vis = 'everyone'
        or (r.presence_vis in ('friends','friends_except') and r.is_friend
            and (r.presence_vis = 'friends' or not r.excl_presence))
        or (r.presence_vis = 'everyone_except' and not r.excl_presence)
        or (r.presence_vis = 'only' and r.excl_presence)
      ) as presence_ok,
      (v_bypass or r.seen_vis = 'everyone'
        or (r.seen_vis in ('friends','friends_except') and r.is_friend
            and (r.seen_vis = 'friends' or not r.excl_seen))
        or (r.seen_vis = 'everyone_except' and not r.excl_seen)
        or (r.seen_vis = 'only' and r.excl_seen)
      ) as seen_ok,
      (v_bypass or r.about_vis = 'everyone'
        or (r.about_vis in ('friends','friends_except') and r.is_friend
            and (r.about_vis = 'friends' or not r.excl_about))
        or (r.about_vis = 'everyone_except' and not r.excl_about)
        or (r.about_vis = 'only' and r.excl_about)
      ) as about_ok,
      (v_bypass or r.photo_partner or r.photo_vis = 'everyone'
        or (r.photo_vis in ('friends','friends_except') and r.is_friend
            and (r.photo_vis = 'friends' or not r.excl_photo))
        or (r.photo_vis = 'everyone_except' and not r.excl_photo)
        or (r.photo_vis = 'only' and r.excl_photo)
      ) as photo_ok
    from resolved r
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id, 'nickname', f.nickname, 'gender', f.gender, 'age', f.age,
    'country', f.country, 'city', f.city,
    'status', case when f.presence_ok then f.status else 'offline' end,
    'avatar', case when f.photo_ok then f.avatar else '' end,
    'is_registered', f.is_registered,
    'last_seen', case when f.seen_ok then f.last_seen else null end,
    'about', case when f.about_ok then f.about else '' end
  ) order by f.last_seen desc), '[]'::jsonb)
  into rows
  from flags f
  where f.presence_ok;

  return rows;
end;
$fn$;

revoke execute on function public.get_online_users(text, int) from public, anon;
grant execute on function public.get_online_users(text, int) to anon, authenticated, service_role;

-- ── 2) presence_for: paksa status 'offline' bagi user ghost ────────────────
create or replace function public.presence_for(p_uids uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  invisible_uid text;
  arr jsonb;
begin
  select nullif(s.invisible_admin_uid, '') into invisible_uid
    from public.app_settings s where s.id = 'global';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',        p.id,
    'nickname',  p.nickname,
    'gender',    p.gender,
    'age',       p.age,
    'country',   p.country,
    'city',      p.city,
    'is_registered', p.is_registered,
    'avatar',    case when public.privacy_can_view(p.id, 'profile_photo', me)
                      then p.avatar else '' end,
    -- Ghost mode membeli privasi PRESENCE saja: user lain melihat 'offline'.
    -- Pemilik sendiri tetap melihat status aslinya (me = p.id di bawah).
    'status',    case
                   when p.id = me then p.status
                   when exists (select 1 from public.ghost_mode_active g
                                 where g.user_id = p.id and g.expires_at > now())
                     then 'offline'
                   when public.privacy_can_view(p.id, 'presence', me)
                     then p.status else 'offline' end,
    'last_seen', case when public.privacy_can_view(p.id, 'last_seen', me)
                      then p.last_seen else null end,
    'about',     case when public.privacy_can_view(p.id, 'about', me)
                      then p.about else '' end
  )), '[]'::jsonb) into arr
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]))
    and p.id <> coalesce(me, '00000000-0000-0000-0000-000000000000'::uuid)
    and (invisible_uid is null or p.id::text <> invisible_uid)
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    );

  return arr;
end;
$function$;

-- ── 3) RPC admin: tampilkan siapa yang sedang ghost ────────────────────────
-- Menjawab "kenapa di admin tidak tercatat": sebelumnya memang TIDAK ADA
-- sumber data untuk itu. Sekarang panel admin bisa menampilkan daftar ghost.
create or replace function public.admin_ghost_users()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  arr jsonb;
begin
  -- Guard SAMA dengan RPC admin lain (mis. admin_stats_users_page).
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'uid', p.id,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'ghost_expires_at', g.expires_at,
    'ghost_sisa_jam', round(extract(epoch from (g.expires_at - now()))/3600.0, 1)
  ) order by g.expires_at desc), '[]'::jsonb)
  into arr
  from public.ghost_mode_active g
  join public.profiles p on p.id = g.user_id
  where g.expires_at > now();

  return arr;
end;
$fn$;

revoke execute on function public.admin_ghost_users() from public, anon;
grant execute on function public.admin_ghost_users() to authenticated, service_role;
