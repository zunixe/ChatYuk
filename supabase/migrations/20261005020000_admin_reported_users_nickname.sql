-- ============================================================
-- Laporan (reports) admin: sertakan NICKNAME pelapor & terlapor supaya
-- jelas "user mana yang dilaporkan".
--
-- LATAR: kartu "Laporan" di Ringkasan admin hanya menampilkan
--   `reported_id` (uid terpotong) + `report_count` → admin tak tahu siapa
--   yang dilaporkan (dan tak bisa membedakan pelapor vs terlapor).
--
-- YANG DIUBAH (HANYA blok `reported_users` di admin_stats_compute):
--   tiap entri kini menyertakan:
--     - reported_nickname : nickname terlapor ('' bila profil sudah hilang)
--     - reported_registered : apakah terlapor user terdaftar
--     - reporters         : daftar ringkas pelapor {id, nickname}
--   Sisa fungsi SALIN PERSIS dari versi live (20261005000000). TIDAK FROZEN.
--
-- CARA APPLY: Management API (lihat APPLIED_VIA_API.md), 1 statement/request.
-- ============================================================

create or replace function public.admin_stats_compute()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
        and not (id = any(v_dummy))),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'registered_users', (select count(*) from profiles
      where is_registered = true and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'anonymous_users', (select count(*) from profiles
      where is_registered = false and not (id = any(v_excl))
        and not (id = any(v_dummy))),
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
      where points = 0 and last_seen >= (now() - interval '7 days')
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
    'points_enabled', (select points_enabled from app_settings where id = 'global'),
    -- ── Versi aplikasi (per INSTALL/device, exclude admin/dev) ──
    -- Distribusi versi dominan (top 10) + total device ber-versi.
    -- URUT: versi TERBARU dulu (semver numerik desc), bukan device terbanyak.
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
          and d.app_version !~ '-'          -- buang versi ber-suffix (build varian)
          and d.app_version ~ '^[0-9]+\.[0-9]+'  -- hanya versi numerik
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
    -- Rata-rata berbobot: bandingkan numerik (major.minor.patch) agar
    -- 1.2.60 vs 1.2.61 tepat.
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
$function$;

-- Verifikasi setelah apply:
--   select jsonb_pretty((public.admin_stats())->'reported_users');
