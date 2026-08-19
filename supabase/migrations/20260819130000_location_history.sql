-- ============================================================
-- ChatYuk: History lokasi per user
-- - Setiap update lokasi (start app / jadi online / ping 5 menit)
--   tercatat ke user_location_history lewat update_my_location.
-- - admin_get_location_history: admin melihat riwayat lat/lon user.
-- ============================================================

-- ── 1. Tabel history ──
create table if not exists public.user_location_history (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  lat        double precision not null,
  lon        double precision not null,
  loc_source text not null default 'gps',
  created_at timestamptz not null default now()
);

create index if not exists user_location_history_user_idx
  on public.user_location_history (user_id, created_at desc);

alter table public.user_location_history enable row level security;

-- Tulis/baca hanya lewat RPC (security definer) — user tidak perlu
-- akses langsung ke tabel.
revoke all on table public.user_location_history from public, anon, authenticated;

-- ── 2. update_my_location sekarang juga mencatat history ──
create or replace function public.update_my_location(
  p_lat double precision,
  p_lon double precision,
  p_source text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;
  update public.profiles
  set lat = p_lat,
      lon = p_lon,
      loc_source = p_source,
      loc_updated_at = now()
  where id = uid;
  -- History posisi tiap update (termasuk saat status berubah ke online).
  insert into public.user_location_history (user_id, lat, lon, loc_source)
  values (uid, p_lat, p_lon, p_source);
end;
$$;

revoke execute on function public.update_my_location(double precision, double precision, text) from public, anon;
grant execute on function public.update_my_location(double precision, double precision, text) to authenticated;

-- ── 3. Admin: riwayat lat/lon user ──
create or replace function public.admin_get_location_history(p_uid uuid, p_limit int default 50)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'lat', h.lat,
      'lon', h.lon,
      'source', h.loc_source,
      'at', h.created_at
    ) order by h.created_at desc
  ), '[]'::jsonb) into result
  from public.user_location_history h
  where h.user_id = p_uid
  limit greatest(p_limit, 1);
  return result;
end;
$$;
revoke execute on function public.admin_get_location_history(uuid, int) from public, anon;
grant execute on function public.admin_get_location_history(uuid, int) to authenticated, service_role;