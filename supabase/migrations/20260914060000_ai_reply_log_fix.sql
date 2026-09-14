-- ============================================================
-- FIX kontrak server AI dummy (menyelesaikan drift 20260914050000)
--
-- Latar (temuan audit 2026-09-14, dari DB live):
--   1) ai_reply_post di DB masih versi LAMA (returns boolean, TANPA log)
--      padahal ai_reply_enqueue versi baru sudah memanggil ai_log_reply →
--      ai_reply_log SELALU 0 baris (observability mati total).
--   2) ai_reply_enqueue live KEHILANGAN dua pengecualian yang ada di file
--      sumber 20260913140000:
--        - ai_always_reply (expert/CS: TIDAK boleh kena rate/cap apa pun)
--        - both-ai_no_rate_limit (Expert x Expert unlimited by design)
--      Akibatnya jalur trigger & edge BEDA kontrak (edge masih lolos).
--   3) 20260914050000 mengubah ai_reply_post jadi VOID, sementara
--      20260914040000 (claim_recovery) memakai `v_ok := ai_reply_post(...)`
--      → kalau di-apply penuh, claim_recovery ERROR (void tak bisa di-assign).
--
-- KEPUTUSAN OWNER (2026-09-14):
--   - ai_reply_post = BOOLEAN ber-log (bukan void) → recovery tetap jalan.
--   - Expert (ai_always_reply) harus SELALU dibalas: lewati cap AI-AI,
--     rate max, rate min. (Gate `hold` TETAP menang — manusia memegang akun;
--     gate itu ada di EDGE function, bukan di trigger.)
--   - ai_active_hours tetap kosmetik (selalu balas) — tidak diubah di sini.
--
-- File ini menggantikan 20260914050000 (yang TIDAK pernah tercatat di
-- schema_migrations & ter-apply sebagian). Semua blok idempoten.
-- ============================================================

-- ── 1. Penulis log internal (tidak pernah raise) ──
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

-- ── 2. ai_reply_post: BOOLEAN + log (kontrak TUNGGAL) ──
-- Dipakai oleh: ai_reply_enqueue (PERFORM), ai_reply_claim_recovery
-- (v_ok := ...), ai_reply_missed_recovery (PERFORM), ai_proactive_tick.
drop function if exists public.ai_reply_post(text, bigint, uuid, uuid, boolean);

create or replace function public.ai_reply_post(
  p_chat_id text,
  p_trigger_msg_id bigint,
  p_sender_id uuid,
  p_dummy_uid uuid,
  p_proactive boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_secret text;
  v_code int;
begin
  select value into v_url from public.ai_internal_config where key = 'ai_reply_url';
  select value into v_secret from public.ai_internal_config where key = 'callback_secret';
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    -- Fail-closed (semua dummy diam) — kini TERCATAT, bukan misteri.
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'skipped:no_secret', '{}');
    return false;
  end if;
  begin
    select status_code into v_code
    from net.http_post(
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
    if v_code < 200 or v_code >= 300 then
      perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'error:http_' || coalesce(v_code::text, 'null'), '{}');
      return false;
    end if;
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'enqueued', jsonb_build_object('proactive', coalesce(p_proactive, false)));
    return true;
  exception when others then
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'error:post_failed', '{}');
    return false;
  end;
end;
$$;

revoke execute on function public.ai_reply_post(text, bigint, uuid, uuid, boolean) from public, anon;
grant execute on function public.ai_reply_post(text, bigint, uuid, uuid, boolean) to authenticated, service_role;

-- ── 3. Trigger enqueue: pulihkan pengecualian yang hilang + log tiap gate ──
-- Kontrak SAMA dengan edge ai-reply (index.ts):
--   - always_reply → bebas cap AI-AI & rate (max/min)
--   - both no_rate_limit di jalur AI-AI → bebas cap 40/jam
create or replace function public.ai_reply_enqueue()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_other uuid;
  v_no_rate boolean;
  v_always_reply boolean;
  v_sender_no_rate boolean;
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

  -- Recipient must be an AI-enabled dummy (ambil config sekalian).
  -- PENTING: pakai IF NOT FOUND (bukan cek null!) — kolom flag boleh null.
  select d.ai_no_rate_limit, d.ai_always_reply, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_always_reply, v_max, v_min
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

  -- ── always_reply (expert/CS): LEWATI semua cap & rate. Pesan selalu enqueue.
  if coalesce(v_always_reply, false) then
    perform public.ai_reply_post(new.chat_id, new.id, new.sender_id, v_other, false);
    return new;
  end if;

  v_max := coalesce(v_max, v_gmax, 30);
  v_min := coalesce(v_min, v_gmin, 5);

  if v_sender_is_dummy then
    -- ── AI↔AI: cap KERAS gabungan 40 pesan/jam — KECUALI kedua dummy
    -- eksplisit no_rate_limit (unlimited by design, mis. Expert×Expert).
    select coalesce(d.ai_no_rate_limit, false) into v_sender_no_rate
    from public.dummy_accounts d where d.uid = new.sender_id;
    if not (coalesce(v_no_rate, false) and coalesce(v_sender_no_rate, false)) then
      select count(*) into v_ai_ai_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id in (v_other, new.sender_id)
        and m.created_at > now() - interval '1 hour';
      if v_ai_ai_1h >= 40 then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:ai_ai_cap', '{}');
        return new;
      end if;
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

-- ── 4. RPC admin baca log (guard is_admin_request) ──
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

-- ── 5. Catat versi (idempoten) ──
insert into supabase_migrations.schema_migrations (version)
values ('20260914060000')
on conflict do nothing;
