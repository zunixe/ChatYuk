-- ============================================================
-- Kecualikan PROFIL PLACEHOLDER ONBOARDING dari statistik/daftar admin.
--
-- KONTEKS (2026-10-02):
--   Trigger `handle_new_user_profile` (20261004070000) membuat baris
--   `profiles` OTOMATIS untuk SETIAP sesi anon (setiap app diboot memanggil
--   `signInAnonymously`). Baris itu diberi nickname "AnonXXXXXXXX" +
--   `needs_onboarding = true` — placeholder sampai user selesai isi nama.
--
--   Baris ini BUKAN user yang memakai fitur "mulai chat tanpa daftar".
--   Ia terbentuk sebelum user sempat memilih. Bila user tutup app / crash /
--   cuma mengintip, placeholder tertinggal dan ikut terhitung di panel
--   admin sebagai "user anon" — membingungkan (mis. "Anon0172D432").
--
--   Terukur live 2026-10-02: 88 profil `AnonXXXXXXXX` needs_onboarding=true,
--   82 dari total 475 profil perlu onboarding. `require_registration=false`.
--
-- PERUBAHAN:
--   1. `admin_stats_compute`: `anonymous_users` & `total_users` TIDAK lagi
--      menghitung profil `needs_onboarding = true`. Kartu Overview anon
--      kini mencerminkan user yang benar-benar melewati onboarding.
--   2. `admin_stats_users_page`: daftar kind 'all'/'anonymous' juga
--      menyembunyikan placeholder `needs_onboarding = true`. kind
--      'registered' TIDAK diubah (user email nyata, walau needs_onboarding
--      masih true karena jalur daftar tertentu — JANGAN disembunyikan).
--
-- CATATAN: `admin_stats_detail` (FROZEN) TIDAK disentuh — UI list user
--   memakai `admin_stats_users_page`, dan `admin_stats_detail` hanya dipakai
--   untuk rooms/messages. `total_users`/`anonymous_users` di sini BUKAN
--   frozen. Body = salinan PERSIS versi live, hanya predikat anon/total yang
--   ditambah filter needs_onboarding. Idempotent (create or replace).
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

-- ── 1) admin_stats_compute: buang placeholder dari total & anon ──────────
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
  -- Alias 'ae' WAJIB: SETOF uuid tanpa alias kolom → referensi 'uuid'
  -- melempar "column uuid does not exist" (42703).
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    -- Placeholder onboarding (needs_onboarding=true) TIDAK dihitung sebagai
    -- user: bukan pilihan user, dibuat trigger. Lihat header.
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
$fn$;

-- ── 2) admin_stats_users_page: sembunyikan placeholder dari list anon/all ──
create or replace function public.admin_stats_users_page(p_kind text default 'all'::text, p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_kind not in ('all','active','registered','anonymous') then
    p_kind := 'all';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  with base as (
    select p.*
      from public.profiles p
     where not (p.id = any(v_dummy))
       -- User dengan device ter-exclude disembunyikan total (bukan sekedar
       -- diberi badge).
       and not (p.id = any(v_excl))
       -- Placeholder onboarding (dibuat trigger, belum dipakai user) hanya
       -- disembunyikan dari list anon/all. User registered TETAP tampil.
       and not (coalesce(p.needs_onboarding, false) and not coalesce(p.is_registered, false))
       and case p_kind
             when 'active' then
               p.last_seen >= current_date at time zone 'Asia/Jakarta'
             when 'registered' then p.is_registered = true
             when 'anonymous' then coalesce(p.is_registered, false) = false
             else true
           end
  ),
  counted as (select count(*) as total from base),
  page as (
    select b.*
      from base b
     -- AKUN TERBARU di atas (created_at desc). Tie-break id agar paginasi stabil.
     order by b.created_at desc nulls last, b.id
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select total from counted),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last, id)
      from page
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

revoke execute on function public.admin_stats_users_page(text, integer, integer) from public, anon;
grant execute on function public.admin_stats_users_page(text, integer, integer) to authenticated, service_role;

-- Verifikasi setelah apply:
--   select position('needs_onboarding' in
--     pg_get_functiondef('public.admin_stats_compute()'::regprocedure)) > 0;   -- true
--   select position('needs_onboarding' in
--     pg_get_functiondef('public.admin_stats_users_page(text,integer,integer)'::regprocedure)) > 0; -- true
