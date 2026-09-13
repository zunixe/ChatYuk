-- admin_ai_settings: HENTIKAN self-heal baris 'global' saat READ.
-- Bug: `insert ... on conflict do nothing` yang tanpa syarat membuat
-- baris 'global' yang sudah dihapus user MUNCUL LAGI setiap kali halaman
-- pengaturan AI dibuka (GET memanggil RPC yang sama tanpa parameter).
-- Fix: pastikan baris hanya saat WRITE field provider (salah satu dari
-- p_api_base/p_api_key/p_default_model/p_stt_base/p_stt_key diisi).
-- Definisi lain identik dengan 20260911170000_is_admin_request_uid.sql.
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

  -- Hanya pastikan baris provider bila ada field provider yang ditulis.
  -- Tanpa ini, baris 'global' yang sengaja dihapus user bangkit lagi
  -- di setiap pembacaan (GET tanpa parameter).
  if p_api_base is not null
     or p_api_key is not null
     or p_default_model is not null
     or p_stt_base is not null
     or p_stt_key is not null then
    insert into public.ai_provider_config (id) values ('global')
    on conflict (id) do nothing;
  end if;

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
