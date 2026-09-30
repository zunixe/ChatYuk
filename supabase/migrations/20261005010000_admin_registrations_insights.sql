-- ============================================================
-- Insight registrasi email untuk dashboard CEO (panel admin Ringkasan).
--
-- LATAR: kartu "Registrasi Email" lama hanya menampilkan bar per-hari dalam
--   satu bulan terpilih. Untuk pengambilan keputusan CEO, dibutuhkan:
--     - KPI: total terdaftar, baru bulan ini, konversi anon→registered,
--       rata-rata/hari, hari terbaik, aktif hari ini.
--     - Tren 12 bulan (apakah tumbuh?).
--     - Sumber akuisisi (Play/FB/organic) — dari user_devices.attribution_*.
--
-- YANG DIBUAT:
--   1. public.admin_registration_kpis() — jsonb ringkasan KPI.
--   2. public.admin_registrations_monthly(p_months) — total per bulan (tren).
--
-- KONSISTENSI: semua angka MENGECUALIKAN dummy + excluded uid (sama seperti
--   admin_registrations_daily) supaya tidak menghitung akun dummy sebagai
--   "user terdaftar" — beda dengan admin_stats_compute (yang hanya eksklusi,
--   bukan dummy). Ini disengaja: KPI CEO = user nyata.
--
-- CARA APPLY: Management API (lihat APPLIED_VIA_API.md), 1 statement/request.
-- ============================================================

-- ── 1. KPI ringkas ──
create or replace function public.admin_registration_kpis()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  v_reg int;
  v_anon int;
  v_month_new int;
  v_prev_month_new int;
  v_today_new int;
  v_best_day int;
  v_best_count int;
  v_days_elapsed int;
  v_avg numeric;
  v_active_today int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  -- Terdaftar (nyata) & anonim (nyata) — untuk konversi.
  select count(*) into v_reg from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy));
  select count(*) into v_anon from public.profiles p
   where p.is_registered = false
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy));

  -- Baru bulan ini & bulan lalu.
  select count(*) into v_month_new from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and date_trunc('month', p.created_at) = date_trunc('month', now());
  select count(*) into v_prev_month_new from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and date_trunc('month', p.created_at) = date_trunc('month', now() - interval '1 month');

  -- Baru hari ini.
  select count(*) into v_today_new from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and p.created_at::date = now()::date;

  -- Hari terbaik bulan ini.
  select extract(day from p.created_at)::int, count(*)::int
    into v_best_day, v_best_count
    from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and date_trunc('month', p.created_at) = date_trunc('month', now())
   group by 1
   order by 2 desc, 1 asc
   limit 1;

  -- Rata-rata/hari bulan ini (bagi jumlah hari yang sudah berjalan).
  v_days_elapsed := extract(day from now())::int;
  v_avg := case when v_days_elapsed > 0
                then round(v_month_new::numeric / v_days_elapsed, 1)
                else 0 end;

  -- Aktif hari ini (registered nyata yang last_seen hari ini).
  select count(*) into v_active_today from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and p.last_seen::date = now()::date;

  return jsonb_build_object(
    'registered_total', v_reg,
    'anon_total', v_anon,
    'conversion_pct', case when (v_reg + v_anon) > 0
        then round(v_reg::numeric * 100 / (v_reg + v_anon), 1) else 0 end,
    'new_this_month', v_month_new,
    'new_prev_month', v_prev_month_new,
    -- Delta % vs bulan lalu (bulan berjalan vs bulan penuh lalu → indikatif).
    'mom_pct', case when v_prev_month_new > 0
        then round((v_month_new - v_prev_month_new)::numeric * 100 / v_prev_month_new, 1)
        else null end,
    'new_today', v_today_new,
    'avg_per_day', v_avg,
    'best_day', v_best_day,
    'best_day_count', coalesce(v_best_count, 0),
    'active_today', v_active_today,
    'days_elapsed', v_days_elapsed
  );
end;
$function$;

-- ── 2. Tren per bulan (12 bulan terakhir) ──
create or replace function public.admin_registrations_monthly(p_months integer default 12)
returns table(ym text, year int, month int, count bigint)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  v_n int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  v_n := least(greatest(coalesce(p_months, 12), 1), 24);

  -- generate_series tiap bulan, LEFT JOIN hitungan, supaya bulan kosong
  -- tetap muncul (garis tren tidak bolong).
  return query
    with m as (
      select date_trunc('month', now())::date - (i || ' months')::interval as mon
      from generate_series(0, v_n - 1) i
    )
    select
      to_char(m.mon, 'YYYY-MM') as ym,
      extract(year from m.mon)::int as year,
      extract(month from m.mon)::int as month,
      coalesce(cnt.c, 0)::bigint as count
    from m
    left join (
      select date_trunc('month', p.created_at) as mon, count(*)::bigint as c
        from public.profiles p
       where p.is_registered = true
         and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
       group by 1
    ) cnt on cnt.mon = m.mon
    order by m.mon asc;
end;
$function$;

revoke execute on function public.admin_registration_kpis() from public, anon;
grant execute on function public.admin_registration_kpis() to authenticated, service_role;

revoke execute on function public.admin_registrations_monthly(integer) from public, anon;
grant execute on function public.admin_registrations_monthly(integer) to authenticated, service_role;

-- Verifikasi setelah apply:
--   select public.admin_registration_kpis();
--   select * from public.admin_registrations_monthly(12);
