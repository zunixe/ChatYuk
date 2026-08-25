-- Device & user tracking (panel admin)
-- Riwayat perangkat permanen: satu baris per (user_id, install_id).

create table if not exists public.user_devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  install_id    text not null,
  brand         text not null default '',
  model         text not null default '',
  os_name       text not null default '',
  os_version    text not null default '',
  app_version   text not null default '',
  ip_address    text not null default '',
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  is_active     boolean not null default true,
  unique (user_id, install_id)
);

create index if not exists user_devices_user_idx on public.user_devices (user_id);
create index if not exists user_devices_seen_idx on public.user_devices (last_seen_at desc);

-- RLS: user hanya bisa menulis/membaca device miliknya sendiri.
alter table public.user_devices enable row level security;
drop policy if exists user_devices_own on public.user_devices;
create policy user_devices_own on public.user_devices
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Client: simpan/perbarui device sendiri (fire-and-forget di login/start).
create or replace function public.upsert_device(
  p_install_id text,
  p_brand text,
  p_model text,
  p_os_name text,
  p_os_version text,
  p_app_version text,
  p_ip text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  insert into public.user_devices
    (user_id, install_id, brand, model, os_name, os_version, app_version, ip_address, last_seen_at, is_active)
  values
    (uid, coalesce(nullif(p_install_id,''), 'unknown'), p_brand, p_model, p_os_name, p_os_version, p_app_version, p_ip, now(), true)
  on conflict (user_id, install_id)
  do update set
    brand        = excluded.brand,
    model        = excluded.model,
    os_name      = excluded.os_name,
    os_version   = excluded.os_version,
    app_version  = excluded.app_version,
    ip_address   = excluded.ip_address,
    last_seen_at = excluded.last_seen_at,
    is_active    = true;
end;
$fn$;

grant execute on function public.upsert_device(text,text,text,text,text,text,text) to authenticated;

-- Admin: daftar semua device semua user.
create or replace function public.admin_list_devices(p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'total', (select count(*) from public.user_devices),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'user_id',      p.id,
        'nickname',     p.nickname,
        'email',        p.email,
        'is_registered', p.is_registered,
        'profile_status', p.status,
        'install_id',   d.install_id,
        'brand',        d.brand,
        'model',        d.model,
        'os_name',      d.os_name,
        'os_version',   d.os_version,
        'app_version',  d.app_version,
        'ip_address',   d.ip_address,
        'last_seen_at', d.last_seen_at,
        'is_active',    d.is_active,
        'created_at',   d.created_at
      ) order by d.last_seen_at desc nulls last
    ), '[]'::jsonb)
  ) into result
  from public.user_devices d
  left join public.profiles p on p.id = d.user_id
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
  return result;
end;
$fn$;

-- Admin: detail lengkap satu user (profil + device + chat partners + lokasi).
create or replace function public.admin_user_detail(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id',        pr.id,
      'nickname',       pr.nickname,
      'gender',         pr.gender,
      'age',            pr.age,
      'country',        pr.country,
      'city',           pr.city,
      'email',          pr.email,
      'is_registered',  pr.is_registered,
      'status',         pr.status,
      'points',         pr.points,
      'ip_address',     pr.ip_address,
      'login_at',       pr.login_at,
      'last_seen',      pr.last_seen,
      'created_at',     pr.created_at,
      'is_dummy',       exists (select 1 from public.dummy_accounts du where du.uid = pr.id)
    ),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'install_id',   d.install_id,
        'brand',        d.brand,
        'model',        d.model,
        'os_name',      d.os_name,
        'os_version',   d.os_version,
        'app_version',  d.app_version,
        'ip_address',   d.ip_address,
        'last_seen_at', d.last_seen_at,
        'is_active',    d.is_active,
        'created_at',   d.created_at
      ) order by d.last_seen_at desc nulls last)
      from public.user_devices d where d.user_id = p_uid
    ), '[]'::jsonb),
    'chats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'chat_id', c.chat_id,
        'participant_names', c.participant_names,
        'participants', c.participants,
        'last_message', c.last_message,
        'last_message_at', c.last_message_at,
        'message_count', (select count(*) from public.private_messages m where m.chat_id = c.chat_id)
      ) order by c.last_message_at desc nulls last)
      from public.private_chats c
      where c.participants @> array[p_uid]::uuid[]
    ), '[]'::jsonb),
    'location_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lat', h.lat,
        'lon', h.lon,
        'source', h.loc_source,
        'at', h.created_at
      ) order by h.created_at desc)
      from public.user_location_history h where h.user_id = p_uid
    ), '[]'::jsonb)
  ) into result
  from public.profiles pr
  where pr.id = p_uid;

  if result is null then
    raise exception 'User not found';
  end if;
  return result;
end;
$fn$;

revoke execute on function public.upsert_device(text,text,text,text,text,text,text) from anon;
revoke execute on function public.admin_list_devices(integer,integer) from public, anon;
revoke execute on function public.admin_user_detail(uuid) from public, anon;
