-- ChatYuk: AI mode for dummy accounts.
-- - dummy_accounts: ai_enabled + ai_persona + ai_model
-- - app_settings: ai_global_enabled, ai_max_replies_per_hour, ai_min_interval_sec
-- - RPC admin_set_dummy_ai, admin_ai_settings, admin_get_ai_settings
-- - admin_list_dummies: include ai fields
-- - trigger ai_reply_enqueue on private_messages AFTER INSERT:
--    real-user message to an AI dummy -> async POST to edge function ai-reply
-- Guards: text-only, sender not a dummy, global on, per-chat rate limits.
-- ============================================================

-- 1. dummy_accounts columns
alter table public.dummy_accounts
  add column if not exists ai_enabled boolean not null default false,
  add column if not exists ai_persona jsonb not null default '{}'::jsonb,
  add column if not exists ai_model text not null default 'glm-5.3-flash';

-- 2. app_settings columns (global kill switch + rate limits)
alter table public.app_settings
  add column if not exists ai_global_enabled boolean not null default true,
  add column if not exists ai_max_replies_per_hour integer not null default 20,
  add column if not exists ai_min_interval_sec integer not null default 2;

-- 3. admin_list_dummies: add ai fields (same shape as before + extras)
create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows jsonb[];
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;
revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;

-- 4. Toggle AI + persona per dummy
create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts where uid = p_uid) then
    raise exception 'dummy_not_found';
  end if;
  update public.dummy_accounts
  set ai_enabled = p_enabled,
      ai_persona = coalesce(p_persona, '{}'::jsonb)
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;
revoke execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb) from public, anon;
grant execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb) to authenticated, service_role;

-- 5. Global AI settings (admin panel)
create or replace function public.admin_ai_settings(
  p_global_enabled boolean default null,
  p_max_replies integer default null,
  p_min_interval integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.app_settings;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  insert into public.app_settings (id) values ('global')
  on conflict (id) do nothing;

  update public.app_settings
  set ai_global_enabled = coalesce(p_global_enabled, ai_global_enabled),
      ai_max_replies_per_hour = coalesce(p_max_replies, ai_max_replies_per_hour),
      ai_min_interval_sec = coalesce(p_min_interval, ai_min_interval_sec),
      updated_at = now()
  where id = 'global'
  returning * into v_row;

  return jsonb_build_object(
    'ai_global_enabled', v_row.ai_global_enabled,
    'ai_max_replies_per_hour', v_row.ai_max_replies_per_hour,
    'ai_min_interval_sec', v_row.ai_min_interval_sec
  );
end;
$$;
revoke execute on function public.admin_ai_settings(boolean, integer, integer) from public, anon;
grant execute on function public.admin_ai_settings(boolean, integer, integer) to authenticated, service_role;

-- 6. Trigger: enqueue AI reply (async, non-blocking via pg_net)
create or replace function public.ai_reply_enqueue()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_other uuid;
  v_global boolean;
  v_max int;
  v_min int;
  v_dummy_out_1h int;
  v_last_dummy_out timestamptz;
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

  -- Recipient must be an AI-enabled dummy
  if not exists (
    select 1 from public.dummy_accounts d
    where d.uid = v_other and d.ai_enabled = true
  ) then
    return new;
  end if;

  -- Sender must NOT be a dummy (no dummy-to-dummy loops, no AI replying
  -- to admin's own outgoing messages while holding the dummy session)
  if exists (select 1 from public.dummy_accounts d where d.uid = new.sender_id) then
    return new;
  end if;

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec
  into v_global, v_max, v_min
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    return new;
  end if;
  v_max := coalesce(v_max, 20);
  v_min := coalesce(v_min, 2);

  -- Per-chat rate limits (proxy: dummy outgoing messages)
  select count(*) into v_dummy_out_1h
  from public.private_messages m
  where m.chat_id = new.chat_id
    and m.sender_id = v_other
    and m.created_at > now() - interval '1 hour';
  if v_dummy_out_1h >= v_max then
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

  -- EXCEPTION-SAFE: kegagalan enqueue (pg_net down, dsb) TIDAK BOLEH
  -- menggagalkan insert pesan user — fitur AI tidak boleh mengganggu
  -- jalur chat utama.
  begin
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-reply',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'chat_id', new.chat_id,
        'trigger_msg_id', new.id,
        'sender_id', new.sender_id,
        'dummy_uid', v_other
      )
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists ai_reply_enqueue_trigger on public.private_messages;
create trigger ai_reply_enqueue_trigger
  after insert on public.private_messages
  for each row execute function public.ai_reply_enqueue();
