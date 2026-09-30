-- ============================================================
-- PEMBERSIH "USER HANTU" + PANTAU PERTUMBUHANNYA.
--
-- LATAR (insiden 2026-10-02, docs/INCIDENT_STALE_CLEANUP_MASS_DELETE.md):
--   1646 dari 1671 arsip `stale_cleanup` ternyata BUKAN user menganggur,
--   melainkan baris `auth.users` yang `profiles`-nya tidak pernah dibuat:
--   nickname '', created_at NULL, last_seen_at NULL, tanpa device.
--
--   Penyebab: `AuthProvider._init` memanggil `signInAnonymously()` lalu
--   `getProfile()`; bila profil tidak ada, profil TIDAK dibuat. Setiap
--   sesi anon yang tidak dilanjutkan ke `registerProfile` (user tutup app,
--   hanya lihat-lihat, crash) meninggalkan satu baris hantu. TIDAK ada
--   trigger di `auth.users` yang membuat profil otomatis (diverifikasi).
--
--   Baris hantu ini "sampah teknis" — beda kategori dari "akun menganggur".
--   Jangan bersihkan lewat `cleanup_stale_anonymous` (fungsi itu untuk akun
--   menganggur, dan logika lamanya fail-open → mass delete).
--
-- YANG DIBUAT:
--   1. `public.purge_ghost_users(p_min_age_hours, p_dry_run)` — hapus HANYA
--      baris `auth.users` anon yang:
--        - tidak punya baris `profiles`, DAN
--        - TIDAK punya jejak apa pun (device, chat, pesan, koin, poin,
--          lokasi, foto, blok, report, contact_message), DAN
--        - umur `auth.users.created_at` >= p_min_age_hours (default 24 jam;
--          beri jeda supaya sesi yang sedang berjalan tidak ikut terhapus).
--      `p_dry_run = true` mengembalikan daftar TANPA menghapus (default
--      aman: WAJIB dipanggil dengan false secara eksplisit untuk hapus).
--      Fail-safe: bila ada jejak apa pun → TIDAK dihapus.
--   2. `public.admin_ghost_stats()` — jumlah hantu + tren untuk panel admin.
--   3. Cron harian `purge_ghost_users` (jam 05:10, setelah cleanup 04:00).
--
-- PRINSIP: setiap kondisi adalah "hanya hapus bila TERBUKTI kosong".
-- Kebalikan dari bug fail-open yang menyebabkan insiden ini.
--
-- Tidak FROZEN. CARA APPLY: Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.purge_ghost_users(
  p_min_age_hours integer default 24,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_ids uuid[];
  v_count int := 0;
  v_uid uuid;
  v_result jsonb;
begin
  -- Kandidat: anon tanpa profil, cukup umur, dan TANPA jejak apa pun.
  -- Setiap `not exists` WAJIB (fail-safe: ada jejak → tidak dihapus).
  select coalesce(array_agg(u.id), '{}')
    into v_ids
    from auth.users u
    left join public.profiles p on p.id = u.id
   where u.is_anonymous = true
     and u.email is null
     and p.id is null                       -- tanpa profil = hantu
     and u.created_at is not null
     and u.created_at < now() - make_interval(hours => p_min_age_hours)
     and not exists (select 1 from public.dummy_accounts d where d.uid = u.id)
     -- jejak wajib kosong:
     and not exists (select 1 from public.user_devices d where d.user_id = u.id)
     and not exists (select 1 from public.user_location_history l where l.user_id = u.id)
     and not exists (select 1 from public.user_photos ph where ph.user_id = u.id)
     and not exists (select 1 from public.private_chats c where c.participants @> array[u.id]::uuid[])
     and not exists (select 1 from public.private_messages m where m.sender_id = u.id)
     and not exists (select 1 from public.coin_ledger k where k.user_id = u.id)
     and not exists (select 1 from public.point_events e where e.user_id = u.id)
     and not exists (select 1 from public.blocks b where b.blocker_id = u.id or b.blocked_id = u.id)
     and not exists (select 1 from public.reports r where r.reporter_id = u.id or r.reported_id = u.id)
     and not exists (select 1 from public.contact_messages cm where cm.user_id = u.id);

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'count', coalesce(array_length(v_ids, 1), 0),
      'ids', to_jsonb(v_ids)
    );
  end if;

  -- Hapus satu per satu; satu kegagalan tidak menggagalkan sisanya.
  foreach v_uid in array v_ids loop
    begin
      delete from auth.users where id = v_uid;
      v_count := v_count + 1;
    exception when others then
      null;
    end;
  end loop;

  v_result := jsonb_build_object(
    'dry_run', false,
    'count', v_count,
    'candidates', coalesce(array_length(v_ids, 1), 0)
  );
  return v_result;
end;
$fn$;

-- ── Statistik hantu untuk panel admin ──
create or replace function public.admin_ghost_stats()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from auth.users u
                left join public.profiles p on p.id = u.id
               where u.is_anonymous and u.email is null and p.id is null),
    -- Hantu yang sudah cukup umur = siap dibersihkan (oleh cron 05:10).
    'purgeable', (select count(*) from auth.users u
                    left join public.profiles p on p.id = u.id
                   where u.is_anonymous and u.email is null and p.id is null
                     and u.created_at < now() - interval '24 hours'),
    -- 7 hari terakhir: berapa hantu baru lahir per hari.
    'daily_new', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day, 'n', d.n)
                       order by d.day)
      from (
        select (u.created_at at time zone 'UTC')::date as day, count(*) as n
          from auth.users u
          left join public.profiles p on p.id = u.id
         where u.is_anonymous and u.email is null and p.id is null
           and u.created_at > now() - interval '7 days'
         group by 1
      ) d
    ), '[]'::jsonb),
    -- Total anon hidup (pembanding: hantu seharusnya jauh lebih kecil).
    'anon_total', (select count(*) from auth.users
                    where is_anonymous and email is null)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.purge_ghost_users(integer, boolean)
  from public, anon, authenticated;
grant execute on function public.purge_ghost_users(integer, boolean)
  to service_role;

revoke execute on function public.admin_ghost_stats()
  from public, anon;
grant execute on function public.admin_ghost_stats()
  to authenticated, service_role;

-- Cron harian 05:10 — SETELAH cleanup_stale_anonymous (04:00) supaya
-- tidak berebut lock dengan pembersihan akun menganggur.
select cron.schedule(
  'purge_ghost_users',
  '10 5 * * *',
  $$select public.purge_ghost_users(24, false)$$
);

-- Verifikasi setelah apply:
--   1) DRY RUN dulu (default true → tidak menghapus):
--      select public.purge_ghost_users(24);          -- lihat count + ids
--   2) Statistik:
--      select public.admin_ghost_stats();
--   3) Cron terjadwal:
--      select jobid, schedule, command from cron.job
--       where command like '%purge_ghost_users%';
