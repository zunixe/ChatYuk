-- ============================================================
-- AI providers: satu baris global → DAFTAR provider yang bisa dipilih
--
-- Permintaan owner (panel admin > AI Bot):
--   - List provider; klik = expand (model, base URL, API key).
--   - Radio/centang = provider yang dipakai.
--   - Bisa tambah provider baru.
--   - Field STT dihapus dari UI (kolom DB + edge tetap, config beku).
--
-- Desain:
--   - ai_provider_config.label = nama tampil ('B.AI', 'OpenRouter'...).
--   - ai_provider_config.is_active = provider yang dipakai (tepat SATU,
--     partial unique index). Fallback edge: baris 'global' lama.
--   - RPC admin-guarded: list / save (upsert, id kosong = tambah baru) /
--     delete (aktif tidak boleh dihapus) / activate.
-- ============================================================

alter table public.ai_provider_config
  add column if not exists label text not null default '',
  add column if not exists is_active boolean not null default false;

-- Backfill: label dari host base URL; baris 'global' jadi aktif.
update public.ai_provider_config
set label = coalesce(
  nullif(split_part(split_part(replace(replace(coalesce(api_base, ''), 'https://', ''), 'http://', ''), '/', 1), '.', 1), ''),
  id
),
is_active = (id = 'global');

-- Tepat satu provider aktif dalam satu waktu.
drop index if exists public.ai_provider_config_one_active;
create unique index ai_provider_config_one_active
  on public.ai_provider_config ((is_active = true))
  where is_active = true;

-- List semua provider (termasuk key — hanya admin via RPC ini).
create or replace function public.admin_ai_provider_list()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
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
      'is_active', p.is_active,
      'updated_at', p.updated_at
    ) order by p.is_active desc, p.updated_at desc)
    from public.ai_provider_config p
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.admin_ai_provider_list() from public, anon;
grant execute on function public.admin_ai_provider_list() to authenticated, service_role;

-- Simpan (upsert): p_id kosong/null = tambah provider baru (slug dari label).
create or replace function public.admin_ai_provider_save(
  p_id text default null,
  p_label text default null,
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
  v_id text;
  v_slug text;
  v_label text;
  v_row public.ai_provider_config;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  -- Normalisasi input di awal (hindari nesting 3 level dalam 1 ekspresi —
  -- endpoint Management API gagal parse pola itu).
  v_id := btrim(coalesce(p_id, ''));
  if v_id = '' then v_id := null; end if;
  v_label := btrim(coalesce(p_label, ''));
  if v_label = '' then v_label := null; end if;

  if v_id is null then
    -- Slug dari label; fallback berurutan bila bentrok/kosong.
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
    insert into public.ai_provider_config (id, label, api_base, api_key, default_model, is_active)
    values (v_id, v_label,
            coalesce(p_api_base, ''), coalesce(p_api_key, ''),
            coalesce(p_default_model, ''), false)
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
    'is_active', v_row.is_active
  );
end;
$$;

revoke execute on function public.admin_ai_provider_save(text, text, text, text, text) from public, anon;
grant execute on function public.admin_ai_provider_save(text, text, text, text, text) to authenticated, service_role;

-- Hapus provider (yang aktif tidak boleh — aktifkan yang lain dulu).
create or replace function public.admin_ai_provider_delete(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_active boolean;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select p.is_active into v_active
  from public.ai_provider_config p where p.id = p_id;
  if v_active is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;
  if v_active then
    raise exception 'PROVIDER_ACTIVE';
  end if;
  delete from public.ai_provider_config where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

revoke execute on function public.admin_ai_provider_delete(text) from public, anon;
grant execute on function public.admin_ai_provider_delete(text) to authenticated, service_role;

-- Aktifkan satu provider (yang dipakai edge function).
create or replace function public.admin_ai_provider_activate(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.ai_provider_config where id = p_id) then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;
  update public.ai_provider_config set is_active = false where is_active = true;
  update public.ai_provider_config set is_active = true, updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

revoke execute on function public.admin_ai_provider_activate(text) from public, anon;
grant execute on function public.admin_ai_provider_activate(text) to authenticated, service_role;
