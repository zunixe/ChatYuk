-- Provider config untuk dummy AI (base URL + API key + model default),
-- editable dari admin panel (AI Bot sheet). Disimpan di tabel TERPISAH
-- dari app_settings karena app_settings punya policy SELECT public
-- (dibaca client untuk toggle fitur) — API key TIDAK BOLEH bocor ke client.
-- ai_provider_config: RLS enabled + TANPA policy = deny semua; hanya
-- service_role (edge function) & RPC security definer (admin-guarded)
-- yang bisa akses.

create table if not exists public.ai_provider_config (
  id text primary key default 'global',
  api_base text,
  api_key text,
  default_model text,
  updated_at timestamptz not null default now()
);

alter table public.ai_provider_config enable row level security;

-- dummy_accounts.ai_model jadi nullable: NULL = ikuti default_model global.
alter table public.dummy_accounts alter column ai_model drop not null;
alter table public.dummy_accounts alter column ai_model set default null;
update public.dummy_accounts set ai_model = null;

-- admin_ai_settings: drop versi 4-param, buat 7-param (tambah provider).
drop function if exists public.admin_ai_settings(boolean, integer, integer, boolean);
create or replace function public.admin_ai_settings(
  p_global_enabled boolean default null,
  p_max_replies integer default null,
  p_min_interval integer default null,
  p_guard_enabled boolean default null,
  p_api_base text default null,
  p_api_key text default null,
  p_default_model text default null
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

  insert into public.ai_provider_config (id) values ('global')
  on conflict (id) do nothing;

  update public.ai_provider_config
  set api_base = coalesce(p_api_base, api_base),
      api_key = coalesce(p_api_key, api_key),
      default_model = coalesce(p_default_model, default_model),
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
    'ai_default_model', v_prov.default_model
  );
end;
$$;
revoke execute on function public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text) from public, anon;
grant execute on function public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text) to authenticated, service_role;
