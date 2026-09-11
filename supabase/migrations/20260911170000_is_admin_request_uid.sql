-- Guard admin anti-rentan: JWT kadang TIDAK membawa claim email (mis.
-- token hasil restore/swap sesi) → auth.email() null → semua RPC admin
-- gagal 'Unauthorized' walau sesi benar. Solusi: cek email dari DATABASE
-- via auth.uid() (auth.users), selain jalur lama.
create or replace function public.is_admin_request()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(auth.email(), '') = 'zunixe@gmail.com'
      or auth.role() = 'service_role'
      or (select lower(coalesce(email, '')) from auth.users where id = auth.uid()) = 'zunixe@gmail.com'
$$;

-- 1) admin_update_dummy_profile (yang gagal tadi)
create or replace function public.admin_update_dummy_profile(
  p_uid uuid,
  p_nickname text,
  p_gender text,
  p_age int,
  p_country text,
  p_city text
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
  if p_gender not in ('male', 'female') then
    raise exception 'Gender tidak valid';
  end if;
  if p_age < 18 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  if length(trim(p_nickname)) < 3 or length(p_nickname) > 20 then
    raise exception 'Nickname harus 3-20 karakter';
  end if;
  update public.profiles
  set nickname = p_nickname, gender = p_gender, age = p_age,
      country = p_country, city = p_city, last_seen = now()
  where id = p_uid;
  update public.dummy_accounts set nickname = p_nickname where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;

-- 2) admin_set_dummy_ai (5-param terbaru)
drop function if exists public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean);
create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb,
  p_schedule_auto boolean default null,
  p_guard_enabled boolean default null
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
      ai_guard_enabled = p_guard_enabled
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;
revoke execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean) from public, anon;
grant execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean) to authenticated, service_role;

-- 3) admin_list_dummies (field lengkap terbaru)
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
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;
revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;

-- 4) admin_ai_settings (9-param terbaru)
drop function if exists public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text, text, text);
create or replace function public.admin_ai_settings(
  p_global_enabled boolean default null,
  p_max_replies integer default null,
  p_min_interval integer default null,
  p_guard_enabled boolean default null,
  p_api_base text default null,
  p_api_key text default null,
  p_default_model text default null,
  p_stt_base text default null,
  p_stt_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.app_settings;
  v_prov public.ai_provider_config;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  insert into public.app_settings (id) values ('global')
  on conflict (id) do nothing;

  update public.app_settings
  set ai_global_enabled = coalesce(p_global_enabled, ai_global_enabled),
      ai_max_replies_per_hour = coalesce(p_max_replies, ai_max_replies_per_hour),
      ai_min_interval_sec = coalesce(p_min_interval, ai_min_interval_sec),
      ai_guard_enabled = coalesce(p_guard_enabled, ai_guard_enabled),
      updated_at = now()
  where id = 'global'
  returning * into v_row;

  insert into public.ai_provider_config (id) values ('global')
  on conflict (id) do nothing;

  update public.ai_provider_config
  set api_base = coalesce(p_api_base, api_base),
      api_key = coalesce(p_api_key, api_key),
      default_model = coalesce(p_default_model, default_model),
      stt_api_base = coalesce(p_stt_base, stt_api_base),
      stt_api_key = coalesce(p_stt_key, stt_api_key),
      updated_at = now()
  where id = 'global'
  returning * into v_prov;

  return jsonb_build_object(
    'ai_global_enabled', v_row.ai_global_enabled,
    'ai_max_replies_per_hour', v_row.ai_max_replies_per_hour,
    'ai_min_interval_sec', v_row.ai_min_interval_sec,
    'ai_guard_enabled', v_row.ai_guard_enabled,
    'ai_api_base', v_prov.api_base,
    'ai_api_key', v_prov.api_key,
    'ai_default_model', v_prov.default_model,
    'ai_stt_base', v_prov.stt_api_base,
    'ai_stt_key', v_prov.stt_api_key
  );
end;
$$;
revoke execute on function public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text, text, text) from public, anon;
grant execute on function public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text, text, text) to authenticated, service_role;
