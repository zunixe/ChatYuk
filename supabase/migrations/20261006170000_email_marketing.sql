-- ============================================================
-- Email Marketing (admin) — campaign, penerima, event, suppression.
--
-- Alur:
--   admin buat campaign (draft) → admin_email_enqueue() snapshot penerima
--   (profiles is_registered + email terisi, minus suppression) → status
--   'queued' + tulis 1 baris outbox(type='email_batch') → edge function
--   email-worker mengirim via Resend → update status per penerima.
--
-- Tracking: pixel open + redirect click via edge function email-track
--   → tabel email_events + update email_recipients (opened_at/clicked_at).
--
-- Akses: SEMUA via RPC security-definer dengan guard admin email
--   (auth.email() = 'zunixe@gmail.com'). Direct DML dikunci RLS (tanpa policy).
-- ============================================================

-- ── Campaigns ──
create table if not exists public.email_campaigns (
  id              bigint generated always as identity primary key,
  name            text not null default '',
  subject         text not null default '',
  html_body       text not null default '',
  segment         jsonb not null default '{"type":"all_registered"}'::jsonb,
  status          text not null default 'draft'
                    check (status in ('draft','queued','sending','sent','failed')),
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  sent_at         timestamptz,
  -- counter denormalized (di-update saat worker/track)
  total_recipients int not null default 0,
  sent_count       int not null default 0,
  delivered_count  int not null default 0,
  open_count       int not null default 0,
  click_count      int not null default 0,
  bounce_count     int not null default 0,
  unsub_count      int not null default 0,
  last_error       text
);

-- ── Recipients (per user per campaign) ──
create table if not exists public.email_recipients (
  id                  bigint generated always as identity primary key,
  campaign_id         bigint not null references public.email_campaigns(id) on delete cascade,
  uid                 uuid,
  email               text not null,
  status              text not null default 'pending'
                        check (status in ('pending','sent','delivered','opened','clicked','bounced','failed','skipped')),
  provider_message_id text,
  error               text,
  created_at          timestamptz not null default now(),
  sent_at             timestamptz,
  opened_at           timestamptz,
  clicked_at          timestamptz,
  unique (campaign_id, email)
);
create index if not exists idx_email_recipients_pending
  on public.email_recipients(campaign_id, status) where status = 'pending';
create index if not exists idx_email_recipients_email
  on public.email_recipients(email);
-- Lookup pixel/click: (campaign_id, uid)
create index if not exists idx_email_recipients_campaign_uid
  on public.email_recipients(campaign_id, uid);

-- ── Events (log mentah) ──
create table if not exists public.email_events (
  id          bigint generated always as identity primary key,
  campaign_id bigint references public.email_campaigns(id) on delete cascade,
  uid         uuid,
  email       text,
  type        text not null
                check (type in ('open','click','delivered','bounce','complaint','unsubscribe','send')),
  url         text,
  user_agent  text,
  ip          text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_email_events_campaign
  on public.email_events(campaign_id, type, created_at desc);

-- ── Suppressions (jangan kirim lagi) ──
create table if not exists public.email_suppressions (
  email      text primary key,
  uid        uuid,
  reason     text not null default 'unsubscribe'
               check (reason in ('unsubscribe','bounce','complaint')),
  created_at timestamptz not null default now()
);

-- ── RLS: kunci total (akses hanya lewat RPC security definer) ──
alter table public.email_campaigns    enable row level security;
alter table public.email_recipients   enable row level security;
alter table public.email_events       enable row level security;
alter table public.email_suppressions enable row level security;
-- (tanpa policy → tidak ada akses langsung authenticated/anon)

-- ── Kolom setelan di app_settings ──
alter table public.app_settings
  add column if not exists email_marketing_enabled boolean not null default false,
  add column if not exists email_from_name   text not null default 'ChatYuk',
  add column if not exists email_from_address text not null default 'noreply@chatyuk.com',
  add column if not exists email_daily_cap   int  not null default 500;

-- ============================================================
-- Helper guard admin
-- ============================================================
create or replace function public._email_is_admin() returns boolean
language sql stable as $fn$
  select coalesce(auth.email(), '') = 'zunixe@gmail.com'
$fn$;

-- ============================================================
-- RPC: daftar campaign (paged)
-- ============================================================
create or replace function public.admin_email_campaigns_page(
  p_limit int default 50,
  p_offset int default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select c.id, c.name, c.subject, c.segment, c.status, c.created_at, c.sent_at,
           c.total_recipients, c.sent_count, c.delivered_count, c.open_count,
           c.click_count, c.bounce_count, c.unsub_count
    from email_campaigns c
    order by c.created_at desc
    limit greatest(1, least(p_limit, 200)) offset greatest(0, p_offset)
  ) x;
  return res;
end; $$;

revoke execute on function public.admin_email_campaigns_page(int, int) from public, anon;
grant execute on function public.admin_email_campaigns_page(int, int) to authenticated;

-- ============================================================
-- RPC: simpan draft (insert / update)
-- ============================================================
create or replace function public.admin_email_campaign_save(
  p_id bigint,
  p_name text,
  p_subject text,
  p_html text,
  p_segment jsonb default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); new_id bigint;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  if p_id is null or p_id = 0 then
    insert into email_campaigns (name, subject, html_body, segment, created_by)
      values (coalesce(p_name,''), coalesce(p_subject,''), coalesce(p_html,''),
              coalesce(p_segment, '{"type":"all_registered"}'::jsonb), me)
      returning id into new_id;
  else
    update email_campaigns set
      name = coalesce(p_name,''),
      subject = coalesce(p_subject,''),
      html_body = coalesce(p_html,''),
      segment = coalesce(p_segment, segment),
      updated_at = now()
    where id = p_id
    returning id into new_id;
  end if;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $$;

revoke execute on function public.admin_email_campaign_save(bigint,text,text,text,jsonb) from public, anon;
grant execute on function public.admin_email_campaign_save(bigint,text,text,text,jsonb) to authenticated;

-- ============================================================
-- RPC: hapus campaign
-- ============================================================
create or replace function public.admin_email_campaign_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  delete from email_campaigns where id = p_id;
  return jsonb_build_object('ok', true);
end; $$;

revoke execute on function public.admin_email_campaign_delete(bigint) from public, anon;
grant execute on function public.admin_email_campaign_delete(bigint) to authenticated;

-- ============================================================
-- RPC: detail campaign + daftar penerima (paged)
-- ============================================================
create or replace function public.admin_email_campaign_detail(
  p_id bigint,
  p_limit int default 100,
  p_offset int default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb; rec jsonb;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select jsonb_build_object(
    'id', id, 'name', name, 'subject', subject, 'html_body', html_body,
    'segment', segment, 'status', status, 'created_at', created_at,
    'sent_at', sent_at, 'total_recipients', total_recipients,
    'sent_count', sent_count, 'delivered_count', delivered_count,
    'open_count', open_count, 'click_count', click_count,
    'bounce_count', bounce_count, 'unsub_count', unsub_count, 'last_error', last_error
  ) into c from email_campaigns where id = p_id;
  if c is null then raise exception 'Campaign not found'; end if;

  select coalesce(jsonb_agg(y order by y.sent_at desc nulls last), '[]'::jsonb) into rec
  from (
    select r.id, r.uid, r.email, r.status, r.sent_at, r.opened_at, r.clicked_at, r.error
    from email_recipients r
    where r.campaign_id = p_id
    order by r.sent_at desc nulls last
    limit greatest(1, least(p_limit, 500)) offset greatest(0, p_offset)
  ) y;

  return jsonb_build_object('campaign', c, 'recipients', rec);
end; $$;

revoke execute on function public.admin_email_campaign_detail(bigint,int,int) from public, anon;
grant execute on function public.admin_email_campaign_detail(bigint,int,int) to authenticated;

-- ============================================================
-- RPC: estimasi jumlah penerima untuk segment
-- segment: {type:'all_registered'} | {type:'active_days', days:N}
-- ============================================================
create or replace function public.admin_email_estimate_segment(p_segment jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int; t text; days int;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  t := coalesce(p_segment->>'type', 'all_registered');
  if t = 'active_days' then
    days := greatest(1, coalesce((p_segment->>'days')::int, 30));
    select count(*) into n from profiles p
      where p.is_registered = true
        and coalesce(p.email,'') <> ''
        and p.last_seen >= now() - make_interval(days => days)
        and not exists (select 1 from email_suppressions s where s.email = p.email);
  else
    select count(*) into n from profiles p
      where p.is_registered = true
        and coalesce(p.email,'') <> ''
        and not exists (select 1 from email_suppressions s where s.email = p.email);
  end if;
  return jsonb_build_object('count', n);
end; $$;

revoke execute on function public.admin_email_estimate_segment(jsonb) from public, anon;
grant execute on function public.admin_email_estimate_segment(jsonb) to authenticated;

-- ============================================================
-- RPC: enqueue — snapshot penerima + tandai campaign 'queued'
-- ============================================================
create or replace function public.admin_email_enqueue(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; n int; enabled boolean;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select * into c from email_campaigns where id = p_id;
  if c is null then raise exception 'Campaign not found'; end if;
  if c.status in ('queued','sending','sent') then
    return jsonb_build_object('ok', false, 'reason', 'already_' || c.status);
  end if;
  if coalesce(c.subject,'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no_subject');
  end if;
  if coalesce(c.html_body,'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no_body');
  end if;

  select email_marketing_enabled into enabled from app_settings where id = 'global';
  if enabled is not true then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;

  -- Bersihkan penerima lama (kalau re-enqueue setelah reset).
  delete from email_recipients where campaign_id = p_id;

  -- Snapshot penerima: registered + email + bukan suppression.
  insert into email_recipients (campaign_id, uid, email)
  select p_id, p.id, p.email
  from profiles p
  where p.is_registered = true
    and coalesce(p.email,'') <> ''
    and not exists (select 1 from email_suppressions s where s.email = p.email)
    and (
      coalesce(c.segment->>'type','all_registered') <> 'active_days'
      or p.last_seen >= now() - make_interval(days => greatest(1, coalesce((c.segment->>'days')::int, 30)))
    )
  on conflict (campaign_id, email) do nothing;

  select count(*) into n from email_recipients where campaign_id = p_id;

  update email_campaigns set
    status = 'queued', total_recipients = n, sent_count = 0,
    delivered_count = 0, open_count = 0, click_count = 0,
    bounce_count = 0, unsub_count = 0, last_error = null, updated_at = now()
  where id = p_id;

  -- Tandai siap kirim di outbox (email-worker mengurasnya).
  insert into outbox (type, payload) values (
    'email_batch',
    jsonb_build_object('campaign_id', p_id)
  );

  return jsonb_build_object('ok', true, 'recipients', n);
end; $$;

revoke execute on function public.admin_email_enqueue(bigint) from public, anon;
grant execute on function public.admin_email_enqueue(bigint) to authenticated;

-- ============================================================
-- RPC: statistik agregat (dashboard)
-- ============================================================
create or replace function public.admin_email_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select jsonb_build_object(
    'campaigns', count(*),
    'sent_total', coalesce(sum(sent_count),0),
    'delivered_total', coalesce(sum(delivered_count),0),
    'open_total', coalesce(sum(open_count),0),
    'click_total', coalesce(sum(click_count),0),
    'bounce_total', coalesce(sum(bounce_count),0),
    'unsub_total', coalesce(sum(unsub_count),0),
    'suppressed', (select count(*) from email_suppressions),
    'registered_with_email', (
      select count(*) from profiles
      where is_registered = true and coalesce(email,'') <> ''
    )
  ) into res
  from email_campaigns;
  return res;
end; $$;

revoke execute on function public.admin_email_stats() from public, anon;
grant execute on function public.admin_email_stats() to authenticated;

-- ============================================================
-- RPC internal (service_role / worker): ambil & tandai penerima
-- ============================================================
create or replace function public.email_worker_claim(p_campaign_id bigint, p_batch int default 100)
returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; c record;
begin
  select id, subject, html_body from email_campaigns where id = p_campaign_id into c;
  if c is null then return jsonb_build_object('error', 'not_found'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'uid', uid, 'email', email
  )), '[]'::jsonb) into res
  from (
    select id, uid, email from email_recipients
    where campaign_id = p_campaign_id and status = 'pending'
    order by id
    limit greatest(1, least(p_batch, 500))
  ) x;

  update email_campaigns set status = 'sending', updated_at = now()
    where id = p_campaign_id and status = 'queued';

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'subject', c.subject,
    'html_body', c.html_body,
    'recipients', res
  );
end; $$;

revoke execute on function public.email_worker_claim(bigint,int) from public, anon, authenticated;
grant execute on function public.email_worker_claim(bigint,int) to service_role;

-- ============================================================
-- RPC: recount counter campaign dari email_recipients/events
-- ============================================================
create or replace function public.email_recount_campaign(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s int; d int; o int; cl int; bo int; un int;
begin
  select
    count(*) filter (where status in ('sent','delivered','opened','clicked')),
    count(*) filter (where status = 'delivered'),
    count(*) filter (where opened_at is not null),
    count(*) filter (where clicked_at is not null),
    count(*) filter (where status = 'bounced')
  into s, d, o, cl, bo
  from email_recipients where campaign_id = p_id;

  select count(*) into un from email_events
    where campaign_id = p_id and type = 'unsubscribe';

  update email_campaigns set
    sent_count = coalesce(s,0),
    delivered_count = coalesce(d,0),
    open_count = coalesce(o,0),
    click_count = coalesce(cl,0),
    bounce_count = coalesce(bo,0),
    unsub_count = coalesce(un,0),
    updated_at = now()
  where id = p_id;

  return jsonb_build_object('ok', true);
end; $$;

revoke execute on function public.email_recount_campaign(bigint) from public, anon, authenticated;
grant execute on function public.email_recount_campaign(bigint) to service_role;

-- ============================================================
-- Cron: kuras email_batch via email-worker tiap 1 menit
-- (aman: no-op saat tidak ada batch / marketing disabled).
-- ============================================================
select cron.unschedule('chatyuk-email-worker')
where exists (select 1 from cron.job where jobname = 'chatyuk-email-worker');

select cron.schedule(
  'chatyuk-email-worker',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/email-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-app-secret', (select app_shared_secret from public.app_settings where id = 'global')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);


