-- Toggle guard NSFW untuk dummy AI (admin panel > AI Bot sheet).
-- Default ON (perilaku lama). OFF = dummy AI bebas lanjut topik dewasa.
-- Dibaca fresh oleh edge function ai-reply tiap invokasi (realtime).

alter table public.app_settings
  add column if not exists ai_guard_enabled boolean not null default true;

-- admin_ai_settings: drop versi 3-param (hindari overload ambigu),
-- buat ulang 4-param dengan ai_guard_enabled.
drop function if exists public.admin_ai_settings(boolean, integer, integer);
create or replace function public.admin_ai_settings(
  p_global_enabled boolean default null,
  p_max_replies integer default null,
  p_min_interval integer default null,
  p_guard_enabled boolean default null
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
      ai_guard_enabled = coalesce(p_guard_enabled, ai_guard_enabled),
      updated_at = now()
  where id = 'global'
  returning * into v_row;

  return jsonb_build_object(
    'ai_global_enabled', v_row.ai_global_enabled,
    'ai_max_replies_per_hour', v_row.ai_max_replies_per_hour,
    'ai_min_interval_sec', v_row.ai_min_interval_sec,
    'ai_guard_enabled', v_row.ai_guard_enabled
  );
end;
$$;
revoke execute on function public.admin_ai_settings(boolean, integer, integer, boolean) from public, anon;
grant execute on function public.admin_ai_settings(boolean, integer, integer, boolean) to authenticated, service_role;
