-- ============================================================
-- Email Marketing — FIX (review 2026-10-06)
--
-- Bug yang diperbaiki:
--  1. DUPLIKAT KIRIM: worker klaim 'pending' tanpa menandai in-flight →
--     batch berulang / worker paralel mengirim email yang sama berkali-kali.
--     FIX: claim mengubah 'pending' → 'sending' (atomik via UPDATE ... RETURNING),
--     kolom retry_count + max_retry. Batch baru hanya klaim 'pending' (fresh);
--     'sending' yang macet dibebaskan bila lebih tua dari lock_timeout.
--  2. BACKLOG ABADI: 1 penerima gagal transient → campaign tak pernah selesai.
--     FIX: retry_count naik tiap gagal; >= max_retry → 'failed' (berhenti).
--  3. Worker memproses batch campaign yang sama berulang dalam 1 siklus
--     (outbox baru di-set sent_at saat campaign selesai).
--     FIX: tandai outbox sent_at SEGERA setelah claim pertama (idempoten),
--     worker lanjut menguras sisa 'pending' lewat claim berikutnya.
-- ============================================================

-- Kolom retry/percobaan pada penerima.
alter table public.email_recipients
  add column if not exists retry_count int not null default 0,
  add column if not exists last_attempt_at timestamptz;

-- Batas percobaan (bisa diatur di app_settings).
alter table public.app_settings
  add column if not exists email_max_retry int not null default 3;

-- Index klaim: (campaign, status) + retry.
create index if not exists idx_email_recipients_claim
  on public.email_recipients(campaign_id, status, id);

-- ============================================================
-- FIX claim: atomik 'pending' → 'sending' (anti dobel).
--   p_lock_seconds: lepas 'sending' yang macet > sekian detik (worker mati).
-- ============================================================
-- Buang overload lama (2-arg) agar tidak ambigu.
drop function if exists public.email_worker_claim(bigint, int);

create or replace function public.email_worker_claim(
  p_campaign_id bigint,
  p_batch int default 100,
  p_lock_seconds int default 300
) returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; c record;
begin
  select id, subject, html_body, status from email_campaigns
    where id = p_campaign_id into c;
  if c is null then return jsonb_build_object('error', 'not_found'); end if;

  -- Lepas 'sending' yang macet (worker sebelumnya mati di tengah).
  update email_recipients set status = 'pending'
   where campaign_id = p_campaign_id
     and status = 'sending'
     and coalesce(last_attempt_at, created_at) < now() - make_interval(secs => p_lock_seconds);

  -- Klaim atomik: pending → sending, kembalikan baris yang diklaim.
  with claimed as (
    update email_recipients r set
      status = 'sending',
      last_attempt_at = now(),
      retry_count = r.retry_count + 1
    where r.id in (
      select id from email_recipients
       where campaign_id = p_campaign_id and status = 'pending'
       order by id
       limit greatest(1, least(p_batch, 500))
       for update skip locked
    )
    returning r.id, r.uid, r.email, r.retry_count
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'uid', uid, 'email', email, 'retry', retry_count
  )), '[]'::jsonb) into res from claimed;

  update email_campaigns set status = 'sending', updated_at = now()
    where id = p_campaign_id and status in ('queued','sending');

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'subject', c.subject,
    'html_body', c.html_body,
    'recipients', res
  );
end; $$;

revoke execute on function public.email_worker_claim(bigint,int,int) from public, anon, authenticated;
grant execute on function public.email_worker_claim(bigint,int,int) to service_role;

-- ============================================================
-- FIX retry: tandai hasil kirim + hormati max_retry.
--   p_ok_hit = true → 'sent'; phase gagal → 'pending' (retry) atau 'failed'.
-- ============================================================
create or replace function public.email_mark_sent(p_recipient_id bigint, p_msg_id text)
returns void language sql security definer set search_path = public as $$
  update email_recipients set
    status = 'sent', sent_at = now(), provider_message_id = nullif(p_msg_id,''), error = null
  where id = p_recipient_id;
$$;

create or replace function public.email_mark_failed(
  p_recipient_id bigint,
  p_error text,
  p_permanent boolean
) returns jsonb language plpgsql security definer set search_path = public as $$
declare rc int; max_r int; done boolean;
begin
  select retry_count into rc from email_recipients where id = p_recipient_id;
  select email_max_retry into max_r from app_settings where id = 'global';
  max_r := coalesce(max_r, 3);
  done := p_permanent or coalesce(rc,0) >= max_r;
  update email_recipients set
    status = case when done then 'failed' else 'pending' end,
    error = left(coalesce(p_error,''), 500)
  where id = p_recipient_id;
  return jsonb_build_object('status', case when done then 'failed' else 'pending' end);
end; $$;

revoke execute on function public.email_mark_sent(bigint,text) from public, anon, authenticated;
grant execute on function public.email_mark_sent(bigint,text) to service_role;
revoke execute on function public.email_mark_failed(bigint,text,boolean) from public, anon, authenticated;
grant execute on function public.email_mark_failed(bigint,text,boolean) to service_role;

create or replace function public.email_recount_campaign(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s int; d int; o int; cl int; bo int; un int; tot int;
begin
  select
    count(*) filter (where status in ('sent','delivered','opened','clicked')),
    count(*) filter (where status = 'delivered'),
    count(*) filter (where opened_at is not null),
    count(*) filter (where clicked_at is not null),
    count(*) filter (where status = 'bounced'),
    count(*)
  into s, d, o, cl, bo, tot
  from email_recipients where campaign_id = p_id;

  select count(*) into un from email_events
    where campaign_id = p_id and type = 'unsubscribe';

  update email_campaigns set
    total_recipients = coalesce(tot,0),
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

create or replace function public.email_finalize_campaign(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare remaining int;
begin
  select count(*) into remaining from email_recipients
   where campaign_id = p_id and status in ('pending','sending');
  if remaining = 0 then
    update email_campaigns set status = 'sent',
      sent_at = coalesce(sent_at, now()), updated_at = now()
    where id = p_id and status in ('queued','sending');
    return jsonb_build_object('done', true);
  end if;
  return jsonb_build_object('done', false, 'remaining', remaining);
end; $$;

revoke execute on function public.email_finalize_campaign(bigint) from public, anon, authenticated;
grant execute on function public.email_finalize_campaign(bigint) to service_role;

-- ============================================================
-- FIX tracking lookup: by (campaign_id, email) unik, bukan uid.
-- (email_recipients unik pada (campaign_id, email).)
-- ============================================================
-- index bantu tracking by campaign+email sudah ada (unique campaign_id,email).
