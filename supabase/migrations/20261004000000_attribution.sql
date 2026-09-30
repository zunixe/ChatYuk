-- ============================================================
-- ChatYuk — Atribusi sumber user (menu admin "Atribusi")
--
-- Tujuan: admin tahu user datang dari kanal mana (Facebook/IG/Google/
-- TikTok/referral/organik). Sumber data: Play Install Referrer (utm_source,
-- gclid, ttclid) + deep link referral yang sudah ada.
--
-- Desain:
--   - Kolom attribution_* di user_devices (1 baris per install, Q2 opt-a).
--   - TULIS SEKALI: nilai attribution hanya diisi saat pertama tercatat.
--     Resume/re-login berikutnya TIDAK menimpa (coalesce existing) supaya
--     kanal asli (saat install) tidak tergantikan oleh instalasi lama.
--   - upsert_device menerima param attribution OPSIONAL (default '').
--
-- Idempotent (add column if not exists / create or replace).
-- ============================================================

-- ---------- 1. Kolom attribution di user_devices ----------
alter table public.user_devices
  add column if not exists attribution_source text,
  add column if not exists utm_source        text,
  add column if not exists utm_medium        text,
  add column if not exists utm_campaign      text,
  add column if not exists utm_content       text,
  add column if not exists referrer_raw      text,
  add column if not exists attribution_at    timestamptz;

-- Index ringkasan: group by source + urut waktu.
create index if not exists user_devices_attr_source_idx
  on public.user_devices (attribution_source);
create index if not exists user_devices_attr_at_idx
  on public.user_devices (attribution_at desc nulls last);

-- ---------- 2. upsert_device: + attribution (tulis sekali) ----------
-- PENTING: versi ini di-BASE dari fungsi LIVE terkini (9-arg dengan
-- `p_legacy_install_id` + logika migrasi in-place, dari
-- 20260921190000_upsert_device_legacy_migrate.sql) LALU ditambah 6 param
-- attribution → SATU fungsi 15-arg. Overload lama (8/9-arg) & overload
-- 14-arg (bug: tak punya p_legacy_install_id) DIBUANG supaya tidak ambigu —
-- klien memanggil satu signature saja via named args.
drop function if exists public.upsert_device(
  text, text, text, text, text, text, text, text);
drop function if exists public.upsert_device(
  text, text, text, text, text, text, text, text, text);
drop function if exists public.upsert_device(
  text, text, text, text, text, text, text, text,
  text, text, text, text, text, text);

create or replace function public.upsert_device(
  p_install_id text,
  p_brand text,
  p_model text,
  p_os_name text,
  p_os_version text,
  p_app_version text,
  p_ip text,
  p_nickname text default '',
  p_legacy_install_id text default '',
  p_attr_source text default '',
  p_utm_source text default '',
  p_utm_medium text default '',
  p_utm_campaign text default '',
  p_utm_content text default '',
  p_referrer_raw text default ''
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  uid uuid := auth.uid();
  v_new text := coalesce(nullif(trim(p_install_id), ''), 'unknown');
  v_legacy text := nullif(trim(coalesce(p_legacy_install_id, '')), '');
  new_id uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Migrasi in-place: baris lama (install_id legacy) milik user yang SAMA
  -- dipindah ke install_id baru → 1 HP fisik tetap 1 baris.
  if v_legacy is not null and v_legacy <> v_new then
    delete from public.user_devices d
     where d.user_id = uid
       and d.install_id = v_legacy
       and exists (
         select 1 from public.user_devices x
          where x.user_id = uid and x.install_id = v_new
       );
    update public.user_devices
       set install_id = v_new
     where user_id = uid
       and install_id = v_legacy;
  end if;

  insert into public.user_devices
    (user_id, install_id, brand, model, os_name, os_version, app_version,
     ip_address, nickname_snapshot, last_seen_at, is_active,
     attribution_source, utm_source, utm_medium, utm_campaign, utm_content,
     referrer_raw, attribution_at)
  values
    (uid, v_new, p_brand, p_model, p_os_name, p_os_version, p_app_version,
     p_ip, nullif(p_nickname, ''), now(), true,
     nullif(p_attr_source,''), nullif(p_utm_source,''), nullif(p_utm_medium,''),
     nullif(p_utm_campaign,''), nullif(p_utm_content,''), nullif(p_referrer_raw,''),
     case when nullif(p_attr_source,'') is not null then now() else null end)
  on conflict (user_id, install_id)
  do update set
    brand             = excluded.brand,
    model             = excluded.model,
    os_name           = excluded.os_name,
    os_version        = excluded.os_version,
    app_version       = excluded.app_version,
    ip_address        = excluded.ip_address,
    nickname_snapshot = coalesce(excluded.nickname_snapshot,
                                 public.user_devices.nickname_snapshot),
    last_seen_at      = excluded.last_seen_at,
    is_active         = true,
    -- TULIS SEKALI: hanya isi bila kolom existing masih NULL DAN param baru ada.
    attribution_source = coalesce(public.user_devices.attribution_source, excluded.attribution_source),
    utm_source         = coalesce(public.user_devices.utm_source, excluded.utm_source),
    utm_medium         = coalesce(public.user_devices.utm_medium, excluded.utm_medium),
    utm_campaign       = coalesce(public.user_devices.utm_campaign, excluded.utm_campaign),
    utm_content        = coalesce(public.user_devices.utm_content, excluded.utm_content),
    referrer_raw       = coalesce(public.user_devices.referrer_raw, excluded.referrer_raw),
    attribution_at     = coalesce(public.user_devices.attribution_at, excluded.attribution_at)
  returning id into new_id;

  -- Bersihkan duplikat lama (sisa identifier lama) — perilaku LIVE dipertahankan.
  delete from public.user_devices
  where user_id = uid
    and lower(brand) = lower(p_brand)
    and lower(model) = lower(p_model)
    and install_id != v_new
    and id != coalesce(new_id, '00000000-0000-0000-0000-000000000000'::uuid);
end;
$fn$;

-- ACL: signature 15-arg untuk authenticated, cabut anon.
grant execute on function public.upsert_device(
  text,text,text,text,text,text,text,text,text,
  text,text,text,text,text,text) to authenticated, service_role;
revoke execute on function public.upsert_device(
  text,text,text,text,text,text,text,text,text,
  text,text,text,text,text,text) from public, anon;

-- ---------- 3. RPC admin: ringkasan per sumber ----------
create or replace function public.admin_attribution_summary(p_days integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare
  result jsonb;
  v_since timestamptz;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  v_since := case when p_days > 0 then now() - (p_days || ' days')::interval else null end;

  select jsonb_build_object(
    'total', (select count(*) from public.user_devices d
              where (v_since is null or d.attribution_at >= v_since)),
    'sources', coalesce((
      select jsonb_agg(row_to_json(t) order by t.users desc)
      from (
        select
          coalesce(nullif(d.attribution_source,''), 'unknown') as source,
          count(*)::int as users,
          count(distinct d.user_id)::int as unique_users
        from public.user_devices d
        where (v_since is null or d.attribution_at >= v_since)
        group by 1
      ) t
    ), '[]'::jsonb),
    'campaigns', coalesce((
      select jsonb_agg(row_to_json(c) order by c.users desc)
      from (
        select
          coalesce(nullif(d.utm_campaign,''), '(tanpa kampanye)') as campaign,
          coalesce(nullif(d.attribution_source,''), 'unknown') as source,
          count(*)::int as users
        from public.user_devices d
        where (v_since is null or d.attribution_at >= v_since)
          and nullif(d.utm_campaign,'') is not null
        group by 1, 2
        limit 30
      ) c
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;
revoke execute on function public.admin_attribution_summary(integer) from public, anon;
grant execute on function public.admin_attribution_summary(integer) to authenticated, service_role;

-- ---------- 4. RPC admin: daftar user per sumber ----------
create or replace function public.admin_attribution_users_page(
  p_source text default '',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'total', (
      select count(*) from public.user_devices d
      where nullif(p_source,'') is null
         or coalesce(nullif(d.attribution_source,''), 'unknown') = p_source
    ),
    'items', coalesce((
      select jsonb_agg(row_to_json(x) order by x.attribution_at desc nulls last)
      from (
        select
          d.user_id,
          p.nickname,
          p.email,
          p.city,
          p.country,
          p.is_registered,
          coalesce(nullif(d.attribution_source,''), 'unknown') as source,
          d.utm_source,
          d.utm_medium,
          d.utm_campaign,
          d.referrer_raw,
          d.brand,
          d.model,
          d.attribution_at,
          d.created_at
        from public.user_devices d
        left join public.profiles p on p.id = d.user_id
        where nullif(p_source,'') is null
           or coalesce(nullif(d.attribution_source,''), 'unknown') = p_source
        order by d.attribution_at desc nulls last
        limit greatest(p_limit, 1) offset greatest(p_offset, 0)
      ) x
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;
revoke execute on function public.admin_attribution_users_page(text,integer,integer) from public, anon;
grant execute on function public.admin_attribution_users_page(text,integer,integer) to authenticated, service_role;
