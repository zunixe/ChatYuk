-- admin_set_dummy_ai + param opsional p_model (null = tidak diubah).
-- Model di-resolve edge function: per-dummy override -> global default.
-- NULL di ai_model = ikuti ai_provider_config.default_model.
-- Routing edge function ai-reply:
--   mimo-*-free / muse-spark-*-free / dst -> OpenCode Zen (gratis)
--   '*:free' / 'nvidia/*'               -> OpenRouter (gratis)
--   lainnya                             -> B.AI / panel ai_provider_config
-- Drop dulu definisi 9-param agar overload signature tidak menumpuk
-- (pelajaran dari get_online_users / create_story).
drop function if exists public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb);
create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb,
  p_schedule_auto boolean default null,
  p_guard_enabled boolean default null,
  p_max_replies int default null,
  p_min_interval int default null,
  p_no_rate_limit boolean default null,
  p_active_hours jsonb default null,
  p_model text default null
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
      ai_active_hours = coalesce(p_active_hours, ai_active_hours),
      -- p_model kosong/null = tidak diubah; string 'NULL' (uppercase)
      -- dari UI = reset ke default global.
      ai_model = case
        when p_model is null or p_model = '' then ai_model
        when upper(p_model) = 'NULL' then null
        else p_model
      end
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;

revoke execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb, text) from public, anon;
grant execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb, text) to authenticated, service_role;

