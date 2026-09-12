-- Rate limit PER-DUMMY (pola guard): NULL = ikut global (AI Bot),
-- angka = override khusus dummy ini. Flag ai_no_rate_limit (Unlimited)
-- tetap ada — menonaktifkan rate check sepenuhnya untuk dummy tsb.
alter table public.dummy_accounts
  add column if not exists ai_max_replies int,
  add column if not exists ai_min_interval int;

-- Trigger: hormati override per-dummy (max/jam + jeda min), lalu global.
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

  -- Recipient must be an AI-enabled dummy (ambil rate config sekalian)
  select d.ai_no_rate_limit, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if v_no_rate is null then
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled into v_global
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    return new;
  end if;
  v_max := coalesce(v_max, 20);
  v_min := coalesce(v_min, 2);

  if v_sender_is_dummy then
    -- ── AI↔AI: TANPA rate limit (permintaan owner untuk testing).
    -- Satu-satunya stop: matikan Mode AI di salah satu dummy / global.
    null;
  else
    -- ── Sender manusia: rate limit (per-dummy override → global)
    if not coalesce(v_no_rate, false) then
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
    end if;
  end if;

  -- EXCEPTION-SAFE: kegagalan enqueue TIDAK BOLEH menggagalkan insert
  -- pesan user — fitur AI tidak boleh mengganggu jalur chat utama.
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

-- admin_set_dummy_ai: drop 5-param, buat 8-param (+p_max_replies,
-- +p_min_interval: NULL = ikut global; +p_no_rate_limit: NULL = tidak diubah).
drop function if exists public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean);
create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb,
  p_schedule_auto boolean default null,
  p_guard_enabled boolean default null,
  p_max_replies int default null,
  p_min_interval int default null,
  p_no_rate_limit boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts where uid = p_uid) then
    raise exception 'dummy_not_found';
  end if;
  update public.dummy_accounts
  set ai_enabled = p_enabled,
      ai_persona = coalesce(p_persona, '{}'::jsonb),
      ai_schedule_auto = coalesce(p_schedule_auto, ai_schedule_auto),
      ai_guard_enabled = p_guard_enabled,
      ai_max_replies = p_max_replies,
      ai_min_interval = p_min_interval,
      ai_no_rate_limit = coalesce(p_no_rate_limit, ai_no_rate_limit)
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;
revoke execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean) from public, anon;
grant execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean) to authenticated, service_role;

-- admin_list_dummies: + rate limit fields (body live terkini + 3 field).
create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows jsonb[];
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'gender', p.gender,
    'age', p.age,
    'city', p.city,
    'country', p.country,
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_guard_enabled', d.ai_guard_enabled,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true),
    'ai_no_rate_limit', coalesce(d.ai_no_rate_limit, false),
    'ai_max_replies', d.ai_max_replies,
    'ai_min_interval', d.ai_min_interval
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;
revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;
