-- Editor jadwal manual: admin_set_dummy_ai +p_active_hours (jsonb array
-- jam 0-23; NULL = tidak diubah; [] = manual mode/nonaktif).
drop function if exists public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean);
create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb,
  p_schedule_auto boolean default null,
  p_guard_enabled boolean default null,
  p_max_replies int default null,
  p_min_interval int default null,
  p_no_rate_limit boolean default null,
  p_active_hours jsonb default null
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
      ai_no_rate_limit = coalesce(p_no_rate_limit, ai_no_rate_limit),
      ai_active_hours = coalesce(p_active_hours, ai_active_hours)
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;
revoke execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb) from public, anon;
grant execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb) to authenticated, service_role;
