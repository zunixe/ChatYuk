-- ============================================================
-- admin_stats_compute.privacy_users: +field 'call' (privasi Panggilan).
-- Melengkapi 20261009140000_privacy_calls.sql.
-- Salin PERSIS dari live + tambah 1 baris (settings) + 1 klausa (WHERE).
-- Bukan FROZEN.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_stats_compute()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'total_users', (select count(*) from profiles
      where not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false),
    'registered_users', (select count(*) from profiles
      where is_registered = true and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'anonymous_users', (select count(*) from profiles
      where is_registered = false and not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false),
    'messages_today',
      (select count(*) from private_messages where created_at >= current_date at time zone 'Asia/Jakarta') +
      (select count(*) from messages where created_at >= current_date at time zone 'Asia/Jakarta'),
    'rooms_active', (select count(distinct room_id) from room_presence),
    'avg_points', (select round(avg(points)) from profiles where not (id = any(v_excl))
      and not (id = any(v_dummy))),
    'total_points', (select sum(points) from profiles where not (id = any(v_excl))
      and not (id = any(v_dummy))),
    'top_earners', (select coalesce(jsonb_agg(
      jsonb_build_object('nickname', nickname, 'points', points, 'uid', id)
      order by points desc), '[]'::jsonb) from (select id, nickname, points from profiles
      where not (id = any(v_excl)) and not (id = any(v_dummy))
      order by points desc limit 10) t),
    'stuck_users', (select count(*) from profiles
      where points = 0 and is_registered = true and last_seen >= (now() - interval '7 days')
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    -- ── Laporan: nickname pelapor & terlapor (biar jelas siapa dilaporkan) ──
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object(
        'reported_id', s.reported_id,
        'report_count', s.c,
        'reported_nickname', coalesce(rp.nickname, ''),
        'reported_registered', coalesce(rp.is_registered, false),
        'reporters', s.reporters
      )
      order by s.c desc), '[]'::jsonb)
      from (
        select
          r.reported_id,
          count(*) as c,
          coalesce(jsonb_agg(distinct jsonb_build_object(
            'id', r.reporter_id,
            'nickname', coalesce(rpr.nickname, '')
          )), '[]'::jsonb) as reporters
        from public.reports r
        left join public.profiles rpr on rpr.id = r.reporter_id
        group by r.reported_id
        order by c desc
        limit 20
      ) s
      left join public.profiles rp on rp.id = s.reported_id),
    -- ── Privasi: user yang pakai setting NON-default + apa yang diatur ──
    'privacy_users', (select coalesce(jsonb_agg(
      jsonb_build_object(
        'uid', p.id,
        'nickname', p.nickname,
        'is_registered', coalesce(p.is_registered, false),
        'settings', jsonb_strip_nulls(jsonb_build_object(
          'presence',      case when p.presence_visibility      <> 'everyone' then p.presence_visibility      end,
          'last_seen',     case when p.last_seen_visibility     <> 'everyone' then p.last_seen_visibility     end,
          'profile_photo', case when p.profile_photo_visibility <> 'everyone' then p.profile_photo_visibility end,
          'about',         case when p.about_visibility         <> 'everyone' then p.about_visibility         end,
          'story',         case when p.story_visibility         <> 'everyone' then p.story_visibility         end,
          'leaderboard',   case when p.leaderboard_visibility   <> 'everyone' then p.leaderboard_visibility   end
          ,'call',        case when p.call_visibility        <> 'everyone' then p.call_visibility        end
        ))
      ) order by p.nickname), '[]'::jsonb)
      from public.profiles p
     where not (p.id = any(v_excl))
       and not (p.id = any(v_dummy))
       and coalesce(p.needs_onboarding, false) = false
       and (p.presence_visibility       <> 'everyone'
         or p.last_seen_visibility      <> 'everyone'
         or p.profile_photo_visibility  <> 'everyone'
         or p.about_visibility          <> 'everyone'
         or p.story_visibility          <> 'everyone'
         or p.leaderboard_visibility    <> 'everyone'
         or p.call_visibility           <> 'everyone')),
    'points_enabled', (select points_enabled from app_settings where id = 'global'),
    -- ── Versi aplikasi (per INSTALL/device, exclude admin/dev) ──
    'app_versions', coalesce((
      select jsonb_agg(
        jsonb_build_object('version', v.version, 'devices', v.devices)
        order by v.semver desc)
      from (
        select
          d.app_version as version,
          count(*)::int as devices,
          (split_part(d.app_version, '.', 1))::int * 10000
          + coalesce(nullif(split_part(d.app_version, '.', 2), '')::int, 0) * 100
          + coalesce(nullif(split_part(d.app_version, '.', 3), '')::int, 0) as semver
        from public.user_devices d
        where d.app_version <> ''
          and d.app_version !~ '-'
          and d.app_version ~ '^[0-9]+\.[0-9]+'
          and not (d.user_id = any(v_excl))
          and not (d.user_id = any(v_dummy))
        group by 1
        order by 3 desc, 2 desc
        limit 10
      ) v
    ), '[]'::jsonb),
    'app_version_count', (select count(*) from public.user_devices d
      where d.app_version <> ''
        and d.app_version !~ '-'
        and d.app_version ~ '^[0-9]+\.[0-9]+'
        and not (d.user_id = any(v_excl))
        and not (d.user_id = any(v_dummy))),
    'app_version_avg_scaled', (
      select round(avg(
        (split_part(d.app_version, '.', 1))::int * 10000
        + coalesce(nullif(split_part(d.app_version, '.', 2), '')::int, 0) * 100
        + coalesce(nullif(split_part(d.app_version, '.', 3), '')::int, 0)
      ))::int
      from public.user_devices d
      where d.app_version <> ''
        and d.app_version !~ '-'
        and d.app_version ~ '^[0-9]+\.[0-9]+'
        and not (d.user_id = any(v_excl))
        and not (d.user_id = any(v_dummy))
    )
  ) into result;
  return result;
end;
$function$


