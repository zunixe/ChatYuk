-- #1 auth endpoint + #5 URL sentral + #2 cap AI-AI 40/jam.
--
-- ai_internal_config: RLS deny-all (tanpa policy). Hanya fungsi
-- SECURITY DEFINER (owner postgres, bypass RLS) yang bisa baca — klien
-- (anon/authenticated) TIDAK bisa SELECT secret walau tahu nama tabel.
--   'callback_secret' → header x-app-secret untuk ai-reply (fail-closed:
--     tanpa secret, enqueue TIDAK dikirim). Nilai = APP_SHARED_SECRET
--     (di-set juga via `supabase secrets set`, di-insert via API).
--   'ai_reply_url'    → satu-satunya URL callback (ganti hardcoded).
-- ai_reply_post(): SATU-SATUNYA penembak ai-reply dari DB — dipakai
-- trigger ai_reply_enqueue, ai_proactive_tick, ai_reply_claim_recovery.
create table if not exists public.ai_internal_config(
  key text primary key,
  value text not null
);
alter table public.ai_internal_config enable row level security;

insert into public.ai_internal_config(key, value)
values ('ai_reply_url', 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-reply')
on conflict (key) do nothing;

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
    return; -- fail-closed: tanpa secret JANGAN panggil endpoint publik
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
    null;
  end;
end;
$$;

revoke execute on function public.ai_reply_post(text, bigint, uuid, uuid, boolean) from public, anon;
grant execute on function public.ai_reply_post(text, bigint, uuid, uuid, boolean) to authenticated, service_role;

-- ── Trigger enqueue: versi 13110000 + header auth via helper + cap AI-AI ──
-- KONTRAK RATE-LIMIT (trigger vs edge function):
--   trigger = GATE + status presence (idle saat kuota habis). Enqueue yang
--     lolos gate belum tentu dibalas (claim/dedupe di function).
--   edge function = cek FINAL (wajib karena jalur invoke-langsung dari app
--     mem-bypass trigger) + dedupe/claim + eksekusi balasan.
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
    return new;
  end if;

  select x into v_other
  from unnest(
    (select pc.participants from public.private_chats pc where pc.chat_id = new.chat_id)
  ) as x
  where x <> new.sender_id
  limit 1;
  if v_other is null then
    return new;
  end if;

  -- Recipient must be an AI-enabled dummy (ambil rate config sekalian).
  -- PENTING: pakai IF NOT FOUND (bukan cek null!) — kolom flag boleh null.
  select d.ai_no_rate_limit, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if not found then
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec
    into v_global, v_gmax, v_gmin
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
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
        return new;
      end if;

      select max(m.created_at) into v_last_dummy_out
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other;
      if v_last_dummy_out is not null
         and v_last_dummy_out > now() - make_interval(secs => v_min) then
        return new;
      end if;
    end if;
  end if;

  -- Enqueue via helper terpusat (auth header + URL dari config).
  perform public.ai_reply_post(
    new.chat_id, new.id, new.sender_id, v_other, false
  );

  return new;
end;
$$;

-- ── Proactive tick: enqueue via helper (auth) ──
create or replace function public.ai_proactive_tick()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r record;
  v_n int := 0;
begin
  if exists (
    select 1 from public.app_settings
    where id = 'global' and ai_global_enabled = false
  ) then
    return jsonb_build_object('ok', true, 'nudged', 0, 'skipped', 'global_off');
  end if;

  for r in
    select pc.chat_id,
           (select m.sender_id
              from public.private_messages m
             where m.chat_id = pc.chat_id
             order by m.created_at desc limit 1) as last_sender,
           (select max(m.created_at)
              from public.private_messages m
             where m.chat_id = pc.chat_id) as last_at,
           d.uid as dummy_uid
      from public.private_chats pc
      join public.dummy_accounts d
        on d.uid = any (pc.participants) and d.ai_enabled = true
      where coalesce(d.ai_hold_active, false) = false
  loop
    begin
      -- Hanya jika pesan terakhir dari MANUSIA (bukan dummy mana pun)
      if r.last_sender is null then continue; end if;
      if exists (
        select 1 from public.dummy_accounts d2 where d2.uid = r.last_sender
      ) then continue; end if;
      -- Hening >45 menit
      if r.last_at is null or r.last_at > now() - interval '45 minutes' then
        continue;
      end if;
      -- Cooldown 3 jam per chat
      if exists (
        select 1 from public.ai_chat_state s
        where s.chat_id = r.chat_id
          and s.proactive_at > now() - interval '3 hours'
      ) then continue; end if;

      insert into public.ai_chat_state (chat_id, proactive_at, updated_at)
      values (r.chat_id, now(), now())
      on conflict (chat_id) do update
        set proactive_at = now(), updated_at = now();

      perform public.ai_reply_post(
        r.chat_id, null, r.last_sender, r.dummy_uid, true
      );
      v_n := v_n + 1;
    exception when others then
      null;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'nudged', v_n);
end;
$$;

revoke execute on function public.ai_proactive_tick() from public, anon;
grant execute on function public.ai_proactive_tick() to authenticated, service_role;

-- ── Claim recovery: invoke ulang via helper (auth) ──
create or replace function public.ai_reply_claim_recovery()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  r record;
begin
  for r in
    select c.trigger_msg_id, c.dummy_uid, m.chat_id, m.sender_id
    from public.ai_reply_claims c
    join public.private_messages m on m.id = c.trigger_msg_id
    where c.claimed_at < now() - interval '10 minutes'
      and c.claimed_at > now() - interval '1 hour'
      and not exists (
        select 1 from public.private_messages m2
        where m2.chat_id = m.chat_id
          and m2.sender_id = c.dummy_uid
          and m2.id > c.trigger_msg_id
      )
  loop
    begin
      perform public.ai_reply_post(
        r.chat_id, r.trigger_msg_id, r.sender_id, r.dummy_uid, false
      );
      delete from public.ai_reply_claims
        where trigger_msg_id = r.trigger_msg_id;
    exception when others then
      null;
    end;
  end loop;
  delete from public.ai_reply_claims
    where claimed_at < now() - interval '1 hour';
end;
$fn$;

revoke execute on function public.ai_reply_claim_recovery() from public, anon;
grant execute on function public.ai_reply_claim_recovery() to service_role;
