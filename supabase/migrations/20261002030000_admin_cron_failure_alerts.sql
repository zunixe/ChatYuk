-- ============================================================
-- ALARM CRON GAGAL: deteksi job penting yang gagal berulang.
--
-- LATAR (insiden 2026-10-02, lihat docs/INCIDENT_STALE_CLEANUP_MASS_DELETE.md):
--   `cleanup_stale_anonymous` (cron jobid 1) GAGAL 24–28 Sep berturut-turut
--   dengan 'coin_ledger is append-only'. Tidak ada satu pun alarm, sehingga
--   selama 5 hari tidak ada yang menyadari. Akibatnya akun anon menumpuk
--   (~1600) lalu lepas sekaligus saat fungsi akhirnya pulih — memicu
--   lonjakan arsip yang membingungkan admin.
--
--   Pelajaran: job kritikal yang gagal >1× berturut WAJIB terlihat, bukan
--   hanya tenggelam di `cron.job_run_details`.
--
-- YANG DIBUAT:
--   1. Tabel `public.admin_alerts` — catatan alarm (audit + bisa dibaca
--      panel admin). RLS admin-only.
--   2. `public.check_cron_failures(p_lookback_hours)` — pindai
--      `cron.job_run_details`, catat job kritikal yang gagal >= ambang ke
--      admin_alerts (idempoten per job per hari), dan kirim push ke device
--      admin bila token tersedia.
--   3. `public.admin_cron_health()` — status ringkas untuk panel admin
--      (job apa saja yang gagal belakangan ini).
--   4. Cron `check_cron_failures` tiap jam (menit 7).
--
-- Job kritikal (gagal = data rusak/menumpuk): daftar ada di `v_critical`.
--   Daftar sengaja EKSPLISIT (bukan semua job) supaya alarm tidak berisik
--   oleh job kosmetik seperti refresh cache.
--
-- Tidak FROZEN. CARA APPLY: Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

-- ── 1. Tabel alarm admin ──
create table if not exists public.admin_alerts (
  id          bigint generated always as identity primary key,
  kind        text not null,                 -- 'cron_failed' | ...
  severity    text not null default 'warning', -- 'critical' | 'warning' | 'info'
  jobid       bigint,                        -- cron.job.jobid (bila relevan)
  job_name    text,
  message     text not null default '',
  detail      jsonb not null default '{}'::jsonb,
  acknowledged_at timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists admin_alerts_created_idx
  on public.admin_alerts (created_at desc);
create index if not exists admin_alerts_unack_idx
  on public.admin_alerts (created_at desc)
  where acknowledged_at is null;
-- Idempotensi: satu alarm per (kind, jobid, hari) supaya cron jam-an tidak
-- menumpuk baris duplikat untuk kegagalan yang sama.
-- `alert_day` disimpan sebagai kolom generated (UTC) — index expression
-- tidak boleh memakai `created_at::date` (tidak IMMUTABLE karena timezone).
alter table public.admin_alerts
  add column if not exists alert_day date
  generated always as ((created_at at time zone 'UTC')::date) stored;

create unique index if not exists admin_alerts_dedupe_idx
  on public.admin_alerts (kind, coalesce(jobid, -1), alert_day);

alter table public.admin_alerts enable row level security;

drop policy if exists admin_alerts_admin on public.admin_alerts; -- SAFE: hapus-buat ulang policy milik migrasi ini sendiri (idempoten); tabel baru jadi tidak ada policy lama yang tersentuh.
create policy admin_alerts_admin on public.admin_alerts -- SAFE: hanya admin (zunixe@gmail.com) yang boleh lihat/ubah alarm; tidak membuka akses ke anon/authenticated umum.
  for all
  using (coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com')
  with check (coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com');

-- ── 2. Pemindai kegagalan cron ──
create or replace function public.check_cron_failures(
  p_lookback_hours integer default 24
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_inserted int := 0;
  v_rec record;
  v_detail jsonb;
  v_msg text;
  v_token text;
begin
  -- Job kritikal: kegagalan berulang = data menumpuk / fitur rusak.
  -- Sengaja eksplisit, bukan "semua job" (hindari alarm berisik).
  for v_rec in
    with critical(jobid, label) as (
      values
        (1::bigint, 'cleanup_stale_anonymous'),
        (4::bigint, 'purge_inactive_accounts'),
        (28::bigint, 'purge_location_history_90d'),
        (10::bigint, 'purge_expired_stories'),
        (22::bigint, 'ai_reply_log_prune')
    )
    select c.jobid,
           c.label,
           count(*) as fail_count,
           count(*) filter (
             where jrd.return_message not ilike '%startup timeout%'
           ) as fail_real,
           max(jrd.start_time) as last_fail,
           (array_agg(jrd.return_message order by jrd.start_time desc))[1]
             as last_error
      from critical c
      join cron.job_run_details jrd on jrd.jobid = c.jobid
     where jrd.status = 'failed'
       and jrd.start_time > now() - make_interval(hours => p_lookback_hours)
     group by c.jobid, c.label
    -- >=2 kegagalan NYATA = pola, bukan insiden sesaat.
    -- `job startup timeout` = server sibuk (transient), tidak dihitung:
    -- terbukti berisik (job 27: 87/3465 run, semuanya pulih sendiri).
    having count(*) filter (
             where jrd.return_message not ilike '%startup timeout%'
           ) >= 2
  loop
    v_detail := jsonb_build_object(
      'fail_count', v_rec.fail_count,
      'fail_real', v_rec.fail_real,
      'last_fail', v_rec.last_fail,
      'last_error', left(coalesce(v_rec.last_error, ''), 500),
      'lookback_hours', p_lookback_hours,
      -- Status run TERAKHIR — supaya admin tahu apakah masih bermasalah
      -- atau sudah pulih (mis. gagal 5× lalu diperbaiki).
      'currently_ok', (
        select coalesce(
          (array_agg(jrd.status order by jrd.start_time desc))[1] = 'succeeded',
          false
        )
          from cron.job_run_details jrd
         where jrd.jobid = v_rec.jobid
      )
    );
    v_msg := format(
      'Cron "%s" gagal %s× dalam %s jam terakhir. Error terakhir: %s',
      v_rec.label, v_rec.fail_real, p_lookback_hours,
      left(coalesce(v_rec.last_error, '-'), 160)
    );

    begin
      insert into public.admin_alerts
        (kind, severity, jobid, job_name, message, detail)
      values
        ('cron_failed', 'critical', v_rec.jobid, v_rec.label, v_msg, v_detail);
      v_inserted := v_inserted + 1;
    exception when unique_violation then
      -- Sudah ada alarm untuk job ini hari ini — jangan duplikat.
      null;
    end;

    -- Push ke device admin (bila ada token). Diam-diam gagal bila tidak ada
    -- device admin / token kosong — alarm tetap tersimpan di tabel.
    begin
      select d.fcm_token into v_token
        from public.user_devices d
        join public.profiles p on p.id = d.user_id
       where p.email = 'zunixe@gmail.com'
         and d.fcm_token is not null
         and d.fcm_token <> ''
         and coalesce(d.is_active, true)
       order by d.last_seen_at desc nulls last
       limit 1;

      if v_token is not null and v_token <> '' then
        insert into public.outbox (type, payload) values (
          'push',
          jsonb_build_object(
            'token', v_token,
            'title', '⚠️ Cron gagal',
            'body', v_msg,
            'data', jsonb_build_object(
              'type', 'admin_alert',
              'alertKind', 'cron_failed',
              'jobid', v_rec.jobid
            )
          )
        );
      end if;
    exception when others then
      null;  -- jangan gagalkan alarm hanya karena push bermasalah
    end;
  end loop;

  return v_inserted;
end;
$fn$;

-- ── 3. Kesehatan cron untuk panel admin ──
create or replace function public.admin_cron_health(
  p_lookback_hours integer default 168
)
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
    'unack_count', (
      select count(*) from public.admin_alerts where acknowledged_at is null
    ),
    'jobs', coalesce((
      select jsonb_agg(x.obj order by x.fails desc)
      from (
        select jsonb_build_object(
                 'jobid', j.jobid,
                 'name', left(regexp_replace(j.command, '\s+', ' ', 'g'), 120),
                 'fails', count(*) filter (where jrd.status = 'failed'),
                 'runs', count(*),
                 'last_status', (array_agg(jrd.status order by jrd.start_time desc))[1],
                 'last_run', max(jrd.start_time),
                 'last_error', left(coalesce(
                   (array_agg(jrd.return_message order by jrd.start_time desc)
                     filter (where jrd.status = 'failed'))[1], ''
                 ), 300)
               ) as obj,
               count(*) filter (where jrd.status = 'failed') as fails
          from cron.job j
          join cron.job_run_details jrd on jrd.jobid = j.jobid
         where jrd.start_time > now() - make_interval(hours => p_lookback_hours)
         group by j.jobid, j.command
        having count(*) filter (where jrd.status = 'failed') > 0
      ) x
    ), '[]'::jsonb),
    'recent_alerts', coalesce((
      select jsonb_agg(y.obj order by y.created_at desc)
      from (
        select jsonb_build_object(
                 'id', a.id,
                 'kind', a.kind,
                 'severity', a.severity,
                 'job_name', a.job_name,
                 'message', a.message,
                 'acknowledged', a.acknowledged_at is not null,
                 'created_at', a.created_at
               ) as obj,
               a.created_at
          from public.admin_alerts a
         order by a.created_at desc
         limit 20
      ) y
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

-- ── 4. Grant & cron ──
revoke execute on function public.check_cron_failures(integer)
  from public, anon, authenticated;
grant execute on function public.check_cron_failures(integer)
  to service_role;

revoke execute on function public.admin_cron_health(integer)
  from public, anon;
grant execute on function public.admin_cron_health(integer)
  to authenticated, service_role;

-- Jadwalkan tiap jam (menit 7 — hindari bentrok dengan job lain yang
-- berjalan di menit 0/5/10).
select cron.schedule(
  'check_cron_failures',
  '7 * * * *',
  $$select public.check_cron_failures(24)$$
);

-- Verifikasi setelah apply:
--   1) tabel & fungsi ada:
--      select count(*) from public.admin_alerts;
--      select public.check_cron_failures(168);   -- tangkap kegagalan lama
--      select public.admin_cron_health(168);
--   2) cron terjadwal:
--      select jobid, schedule, command from cron.job
--       where command like '%check_cron_failures%';
