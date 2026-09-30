-- ============================================================
-- ChatYuk — stuck_users: hanya user TERDAFTAR (relevan ekonomi YukCoin)
--
-- Konteks: di ekonomi YukCoin, saldo awal SEMUA user = 0 (kecuali klaim
-- welcome bonus anon). Definisi lama `stuck_users` (points = 0 & aktif
-- 7 hari) jadi false-positive: hampir semua user baru anon ikut terhitung
-- "terjebak" padahal itu kondisi normal.
--
-- Perubahan: tambahkan `is_registered = true` → yang dihitung hanya user
-- yang SUDAH daftar email tapi saldo 0 (indikasi tidak pernah topup /
-- tidak dapat income). Definisi selebihnya TIDAK berubah.
--
-- admin_stats_compute BUKAN fungsi FROZEN (tak ada di frozen_functions.txt
-- / snapshot). Body di sini = SALINAN PERSIS versi live (terakhir dari
-- 20260905100000_admin_stats_exclude_dummies.sql) — HANYA baris stuck_users
-- yang diubah. ACL service_role dipertahankan persis.
--
-- Idempotent (create or replace).
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
  -- Alias 'ae' WAJIB: SETOF uuid tanpa alias kolom → referensi 'uuid'
  -- melempar "column uuid does not exist" (42703).
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
    -- DIUBAH: + is_registered = true (lihat header).
    'stuck_users', (select count(*) from profiles
      where points = 0 and is_registered = true
        and last_seen >= (now() - interval '7 days')
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object('reported_id', reported_id, 'report_count', c)
      order by c desc), '[]'::jsonb)
      from (select reported_id, count(*) as c from reports
            group by reported_id order by c desc limit 20) sub),
    'points_enabled', (select points_enabled from app_settings where id = 'global')
  ) into result;
  return result;
end;
$fn$;

-- ACL: pertahankan persis seperti live (hanya service_role; dipanggil oleh
-- admin_stats/admin_stats cache internally).
revoke execute on function public.admin_stats_compute() from public, anon, authenticated;
grant execute on function public.admin_stats_compute() to service_role;

-- Ringkasan admin di-cache; hanguskan agar angka stuck_users langsung segar.
delete from public.admin_stats_cache where id = 1;
