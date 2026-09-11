-- Guard NSFW per-dummy (override global), pola seperti notifikasi:
-- NULL = ikuti global (app_settings.ai_guard_enabled),
-- true/false = override khusus dummy ini.
-- ai-reply: guardOn = dummy.ai_guard_enabled ?? global ?? true.

alter table public.dummy_accounts
  add column if not exists ai_guard_enabled boolean;

-- admin_set_dummy_ai: drop 4-param (hindari overload ambigu), buat 5-param.
-- p_guard_enabled NULL = kembalikan ke "ikuti global".
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
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
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

-- admin_list_dummies: sertakan ai_guard_enabled (+ pertahankan semua
-- field yg ada: gender/age/city/country, ai_*, schedule).
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
