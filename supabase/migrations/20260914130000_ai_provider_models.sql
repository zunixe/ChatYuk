-- ============================================
-- ChatYuk: AI PROVIDER — model CHAT + STORY + FALLBACK (bisa diatur dari UI)
-- ============================================
-- Latar:
--   Sebelumnya model chat = default_model (bisa diatur), tapi model STORY
--   hardcode 'glm-5.3-flash' di edge (ai-reply & ai-daily-life) dan model
--   FALLBACK hardcode 'mimo-v2.5-free'. Owner minta SEMUA bisa diatur dari
--   panel admin tanpa hardcode.
--
-- Perubahan:
--   1) ai_provider_config + kolom `story_model` & `fallback_model`.
--   2) admin_ai_provider_save/list + expose & simpan 2 kolom itu.
--   Edge function (ai-reply, ai-daily-life) membaca ketiganya; bila kosong
--   pakai fallback lama (default_model → 'glm-5.3-flash', 'mimo-v2.5-free').
-- ============================================

alter table public.ai_provider_config
  add column if not exists story_model text not null default '',
  add column if not exists fallback_model text not null default '';

comment on column public.ai_provider_config.story_model is
  'Model untuk cerita harian (ai-daily-life & story di ai-reply). Kosong = ikut default_model.';
comment on column public.ai_provider_config.fallback_model is
  'Model cadangan saat model utama gagal (402/429/5xx). Kosong = mimo-v2.5-free (Zen).';

-- ── admin_ai_provider_save: + p_story_model, p_fallback_model ──
drop function if exists public.admin_ai_provider_save(text, text, text, text, text);
create or replace function public.admin_ai_provider_save(
  p_id text default null,
  p_label text default null,
  p_api_base text default null,
  p_api_key text default null,
  p_default_model text default null,
  p_story_model text default null,
  p_fallback_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_id text;
  v_slug text;
  v_label text;
  v_row public.ai_provider_config;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  v_id := btrim(coalesce(p_id, ''));
  if v_id = '' then v_id := null; end if;
  v_label := btrim(coalesce(p_label, ''));
  if v_label = '' then v_label := null; end if;

  if v_id is null then
    v_slug := lower(regexp_replace(coalesce(p_label, ''), '[^a-z0-9]+', '-', 'gi'));
    v_slug := btrim(v_slug, '-');
    if v_slug is null or v_slug = '' then v_slug := 'provider'; end if;
    v_id := v_slug;
    if exists (select 1 from public.ai_provider_config where id = v_id) then
      v_id := v_slug || '-' || substr(md5(clock_timestamp()::text), 1, 6);
    end if;
    v_label := btrim(coalesce(p_label, ''));
    if v_label = '' then v_label := null; end if;
    if v_label is null then v_label := v_id; end if;
    insert into public.ai_provider_config
      (id, label, api_base, api_key, default_model, story_model, fallback_model, is_active)
    values (v_id, v_label,
            coalesce(p_api_base, ''), coalesce(p_api_key, ''),
            coalesce(p_default_model, ''), coalesce(p_story_model, ''),
            coalesce(p_fallback_model, ''), false)
    returning * into v_row;
  else
    if v_label is null then
      select p.label into v_label
      from public.ai_provider_config p where p.id = v_id;
    end if;
    update public.ai_provider_config
    set label = coalesce(v_label, label),
        api_base = coalesce(p_api_base, api_base),
        api_key = coalesce(p_api_key, api_key),
        default_model = coalesce(p_default_model, default_model),
        story_model = coalesce(p_story_model, story_model),
        fallback_model = coalesce(p_fallback_model, fallback_model),
        updated_at = now()
    where id = v_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'PROVIDER_NOT_FOUND';
    end if;
  end if;

  return jsonb_build_object(
    'id', v_row.id, 'label', v_row.label,
    'api_base', coalesce(v_row.api_base, ''),
    'api_key', coalesce(v_row.api_key, ''),
    'default_model', coalesce(v_row.default_model, ''),
    'story_model', coalesce(v_row.story_model, ''),
    'fallback_model', coalesce(v_row.fallback_model, ''),
    'is_active', v_row.is_active
  );
end;
$function$;
revoke execute on function public.admin_ai_provider_save(text,text,text,text,text,text,text) from public, anon;
grant execute on function public.admin_ai_provider_save(text,text,text,text,text,text,text) to authenticated, service_role;

-- ── admin_ai_provider_list: + story_model, fallback_model ──
create or replace function public.admin_ai_provider_list()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'label', p.label,
      'api_base', coalesce(p.api_base, ''),
      'api_key', coalesce(p.api_key, ''),
      'default_model', coalesce(p.default_model, ''),
      'story_model', coalesce(p.story_model, ''),
      'fallback_model', coalesce(p.fallback_model, ''),
      'is_active', p.is_active,
      'updated_at', p.updated_at
    ) order by p.is_active desc, p.updated_at desc)
    from public.ai_provider_config p
  ), '[]'::jsonb);
end;
$function$;
revoke execute on function public.admin_ai_provider_list() from public, anon;
grant execute on function public.admin_ai_provider_list() to authenticated, service_role;

-- Set model chat+story+fallback provider aktif (b-ai) = qwen3.8-flash.
-- Fallback tetap mimo-v2.5-free (Zen, gratis) — gak diisi = pakai default edge.
update public.ai_provider_config
   set default_model = 'qwen3.8-flash',
       story_model   = 'qwen3.8-flash',
       updated_at = now()
 where id = 'b-ai';
