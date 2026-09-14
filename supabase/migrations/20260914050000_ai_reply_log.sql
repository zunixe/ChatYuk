-- ============================================================
-- Observability pipeline AI: ai_reply_log
--
-- Masalah: pesan tak dibalas tanpa jejak (kasus Dhanu & Sarah,
-- BinorMuda) — hanya bisa ditebak dari code. Setelah migrasi ini
-- SETIAP keputusan tercatat: enqueue trigger, skip gate, balasan edge.
-- Cara baca: docs/AI_DUMMY_DEBUG.md §7.
--
-- Retensi 7 hari (cron harian). RLS deny-all; tulis via SECURITY
-- DEFINER / service_role, baca via RPC admin.
-- ============================================================

create table if not exists public.ai_reply_log(
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  chat_id text,
  trigger_msg_id bigint,
  sender_id uuid,
  dummy_uid uuid,
  proactive boolean not null default false,
  stage text not null,     -- 'enqueue' | 'edge'
  decision text not null,  -- 'enqueued' | 'skipped:<alasan>' | 'replied[:...]' | 'error:...'
  detail jsonb not null default '{}'::jsonb
);
alter table public.ai_reply_log enable row level security;
create index if not exists ai_reply_log_chat_idx on public.ai_reply_log (chat_id, created_at desc);
create index if not exists ai_reply_log_dummy_idx on public.ai_reply_log (dummy_uid, created_at desc);

-- Penulis internal (tidak pernah raise — logging tidak boleh menggagalkan chat).
create or replace function public.ai_log_reply(
  p_chat_id text,
  p_trigger_msg_id bigint,
  p_sender_id uuid,
  p_dummy_uid uuid,
  p_proactive boolean,
  p_stage text,
  p_decision text,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.ai_reply_log(chat_id, trigger_msg_id, sender_id, dummy_uid, proactive, stage, decision, detail)
  values (p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, coalesce(p_proactive, false), p_stage, p_decision, coalesce(p_detail, '{}'::jsonb));
exception when others then
  null;
end;
$$;

revoke execute on function public.ai_log_reply(text, bigint, uuid, uuid, boolean, text, text, jsonb) from public, anon;
grant execute on function public.ai_log_reply(text, bigint, uuid, uuid, boolean, text, text, jsonb) to authenticated, service_role;

-- ai_reply_post: versi ber-log (kontrak & URL sama dengan 13130000).
create or replace function public.ai_reply_post(
  p_chat_id text,
  p_trigger_msg_id bigint,
  p_sender_id uuid,
  p_dummy_uid uuid,
  p_proactive boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_secret text;
begin
  select value into v_url from public.ai_internal_config where key = 'ai_reply_url';
  select value into v_secret from public.ai_internal_config where key = 'callback_secret';
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    -- fail-closed (semua dummy diam) — kini TERCATAT, bukan misteri.
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'skipped:no_secret', '{}');
    return;
  end if;
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-app-secret', v_secret
      ),
      body := jsonb_build_object(
        'chat_id', p_chat_id,
        'trigger_msg_id', p_trigger_msg_id,
        'sender_id', p_sender_id,
        'dummy_uid', p_dummy_uid,
        'proactive', coalesce(p_proactive, false)
      )
    );
  exception when others then
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'error:post_failed', '{}');
    return;
  end;
  perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'enqueued', jsonb_build_object('proactive', coalesce(p_proactive, false)));
end;
$$;

revoke execute on function public.ai_reply_post(text, bigint, uuid, uuid, boolean) from public, anon;
grant execute on function public.ai_reply_post(text, bigint, uuid, uuid, boolean) to authenticated, service_role;

-- Trigger enqueue: logika IDENTIK dengan 13130000 + log tiap gate.
-- Kontrak rate-limit tidak berubah (lihat komentar di 13130000).
create or replace function public.ai_reply_enqueue()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_other uuid;
  v_no_rate boolean;
  v_sender_is_dummy boolean;
  v_global boolean;
  v_max int;
  v_min int;
  v_gmax int;
  v_gmin int;
  v_dummy_out_1h int;
  v_last_dummy_out timestamptz;
  v_ai_ai_1h int;
begin
  -- Only plain text messages
  if coalesce(new.type, 'text') != 'text' then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null, false, 'enqueue', 'skipped:non_text', '{}');
    return new;
  end if;

  select x into v_other
  from unnest(
    (select pc.participants from public.private_chats pc where pc.chat_id = new.chat_id)
  ) as x
  where x <> new.sender_id
  limit 1;
  if v_other is null then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null, false, 'enqueue', 'skipped:no_other', '{}');
    return new;
  end if;

  -- Recipient must be an AI-enabled dummy (ambil rate config sekalian).
  -- PENTING: pakai IF NOT FOUND (bukan cek null!) — kolom flag boleh null.
  select d.ai_no_rate_limit, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if not found then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:dummy_disabled', '{}');
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec
    into v_global, v_gmax, v_gmin
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:global_off', '{}');
    return new;
  end if;
  v_max := coalesce(v_max, v_gmax, 20);
  v_min := coalesce(v_min, v_gmin, 2);

  if v_sender_is_dummy then
    -- ── AI↔AI: cap KERAS gabungan 40 pesan/jam (flag no_rate_limit TIDAK
    -- berlaku di sini) — tanpa ini dummy no-limit ping-pong tanpa henti.
    select count(*) into v_ai_ai_1h
    from public.private_messages m
    where m.chat_id = new.chat_id
      and m.sender_id in (v_other, new.sender_id)
      and m.created_at > now() - interval '1 hour';
    if v_ai_ai_1h >= 40 then
      perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:ai_ai_cap', '{}');
      return new;
    end if;
  else
    -- ── Sender manusia: rate limit (per-dummy override → global)
    if not coalesce(v_no_rate, false) then
      select count(*) into v_dummy_out_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other
        and m.created_at > now() - interval '1 hour';
      if v_dummy_out_1h >= v_max then
        -- Kuota habis → tampil idle (downgrade online→idle saja).
        -- Exception-safe: kolom ai_always_online mungkin belum ada di DB
        -- lama; kegagalan presence TIDAK BOLEH menggagalkan insert pesan.
        begin
          begin
            perform 1 from public.dummy_accounts
              where uid = v_other and coalesce(ai_always_online, false) = true;
            if found then
              null; -- always_online: jangan sentuh presence.
            else
              update public.profiles
                 set status = 'idle', last_seen = now()
               where id = v_other and status = 'online';
            end if;
          exception when undefined_column then
            update public.profiles
               set status = 'idle', last_seen = now()
             where id = v_other and status = 'online';
          end;
        exception when others then
          null;
        end;
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:rate_max', jsonb_build_object('out_1h', v_dummy_out_1h, 'max', v_max));
        return new;
      end if;

      select max(m.created_at) into v_last_dummy_out
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other;
      if v_last_dummy_out is not null
         and v_last_dummy_out > now() - make_interval(secs => v_min) then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:rate_min_interval', '{}');
        return new;
      end if;
    end if;
  end if;

  -- Enqueue via helper terpusat (auth header + URL dari config + log).
  perform public.ai_reply_post(
    new.chat_id, new.id, new.sender_id, v_other, false
  );

  return new;
end;
$$;

-- RPC admin: baca log terakhir (guard is_admin_request).
create or replace function public.admin_get_ai_reply_log(
  p_chat_id text default null,
  p_limit int default 100
)
returns jsonb[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows jsonb[];
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(t.j order by t.id desc), '{}'::jsonb[]) into v_rows
  from (
    select l.id,
      jsonb_build_object(
        'created_at', l.created_at,
        'chat_id', l.chat_id,
        'trigger_msg_id', l.trigger_msg_id,
        'sender_id', l.sender_id,
        'dummy_uid', l.dummy_uid,
        'nickname', (select d.nickname from public.dummy_accounts d where d.uid = l.dummy_uid),
        'proactive', l.proactive,
        'stage', l.stage,
        'decision', l.decision,
        'detail', l.detail
      ) as j
    from public.ai_reply_log l
    where (p_chat_id is null or l.chat_id = p_chat_id)
    order by l.id desc
    limit least(coalesce(p_limit, 100), 500)
  ) t;
  return v_rows;
end;
$$;

revoke execute on function public.admin_get_ai_reply_log(text, int) from public, anon;
grant execute on function public.admin_get_ai_reply_log(text, int) to authenticated, service_role;

-- Retensi 7 hari (cron harian 03:00).
select cron.unschedule('chatyuk-ai-log-cleanup')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-log-cleanup');

select cron.schedule(
  'chatyuk-ai-log-cleanup',
  '0 3 * * *',
  $$delete from public.ai_reply_log where created_at < now() - interval '7 days'$$
);
