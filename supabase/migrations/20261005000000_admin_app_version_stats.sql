-- ============================================================
-- ChatYuk — Ringkasan admin: distribusi versi aplikasi + rata-rata.
--
-- Tujuan: admin tahu "user sekarang rata-rata pakai versi berapa" dan
-- sebarannya (versi mana yang dominan) — untuk memutuskan kapan aman
-- memaksa update.
--
-- Sumber: user_devices.app_version (diisi tiap sync perangkat).
-- Aturan:
--   - Hanya dari user_devices (per-install), dedup per baris device.
--   - Exclude device milik uid ter-exclude & dummy (konsisten admin_stats).
--   - Versi dinormalkan: buang suffix build "-admin"/"-dev"/"-*" — build
--     internal/varian tidak dihitung sebagai "versi user" supaya rata-rata
--     tidak bias. Hanya versi numerik x.y.z yang masuk hitungan.
--   - avg dihitung sebagai rata-rata berbobot (SUM(minor)/count) memakai
--     komponen numerik agar "1.2.60" & "1.2.61" dibandingkan tepat, bukan
--     string.
-- ============================================================

create or replace function public.admin_stats_compute()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object('reported_id', reported_id, 'report_count', c)
      order by c desc), '[]'::jsonb)
      from (select reported_id, count(*) as c from reports
            group by reported_id order by c desc limit 20) sub),
    'points_enabled', (select points_enabled from app_settings where id = 'global'),
    -- ── Versi aplikasi (per INSTALL/device, exclude admin/dev) ──
    -- Distribusi versi dominan (top 10) + total device ber-versi.
    'app_versions', coalesce((
      select jsonb_agg(row_to_json(v) order by v.devices desc)
      from (
        select
          d.app_version as version,
          count(*)::int as devices
        from public.user_devices d
        where d.app_version <> ''
          and d.app_version !~ '-'          -- buang versi ber-suffix (build varian)
          and d.app_version ~ '^[0-9]+\.[0-9]+'  -- hanya versi numerik
          and not (d.user_id = any(v_excl))
          and not (d.user_id = any(v_dummy))
        group by 1
        order by 2 desc
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
    -- 1.2.60 vs 1.2.61 tepat. Ambil rata-rata (major*10000+minor*100+patch)
    -- lalu pecah lagi ke string x.y.z di client.
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
$fn$;
revoke execute on function public.admin_stats_compute() from public, anon;
grant execute on function public.admin_stats_compute() to authenticated, service_role;

-- Bersihkan cache stats (5 menit) supaya field baru langsung terlihat.
do $$
begin
  if to_regclass('public.admin_stats_cache') is not null then
    delete from public.admin_stats_cache;
  end if;
exception when undefined_table then null;
end $$;
