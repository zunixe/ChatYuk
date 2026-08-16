-- ============================================================
-- ChatYuk: Kolom lokasi (lat/lon) untuk fitur "orang sekitar"
-- - lat/lon: koordinat terakhir user
-- - loc_source: 'gps' (presisi, izin diberikan) atau 'ip' (perkiraan)
-- - loc_updated_at: kapan terakhir diperbarui
-- - share_location: toggle user untuk ikut "orang sekitar" (default false)
-- RPC update_my_location dipanggil client (GPS-if-allowed / IP fallback).
-- ============================================================

alter table public.profiles
  add column if not exists lat double precision,
  add column if not exists lon double precision,
  add column if not exists loc_source text,
  add column if not exists loc_updated_at timestamptz,
  add column if not exists share_location boolean not null default false;

-- RPC: user memperbarui lokasinya sendiri.
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
end;
$$;

revoke execute on function public.update_my_location(double precision, double precision, text) from public, anon;
grant execute on function public.update_my_location(double precision, double precision, text) to authenticated;
