-- upsert_device: terima p_nickname (snapshot) + bersihkan duplikat lama
-- akibat install_id random sebelumnya. Pertahankan 1 row per HP fisik
-- (ANDROID_ID) — hapus duplikat lama dengan brand/model sama.

create or replace function public.upsert_device(
  p_install_id text,
  p_brand text,
  p_model text,
  p_os_name text,
  p_os_version text,
  p_app_version text,
  p_ip text,
  p_nickname text default ''
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  uid uuid := auth.uid();
  new_id uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  insert into public.user_devices
    (user_id, install_id, brand, model, os_name, os_version, app_version, ip_address, nickname_snapshot, last_seen_at, is_active)
  values
    (uid, coalesce(nullif(p_install_id,''), 'unknown'), p_brand, p_model, p_os_name, p_os_version, p_app_version, p_ip, nullif(p_nickname,''), now(), true)
  on conflict (user_id, install_id)
  do update set
    brand             = excluded.brand,
    model             = excluded.model,
    os_name           = excluded.os_name,
    os_version        = excluded.os_version,
    app_version       = excluded.app_version,
    ip_address        = excluded.ip_address,
    nickname_snapshot = coalesce(excluded.nickname_snapshot, public.user_devices.nickname_snapshot),
    last_seen_at      = excluded.last_seen_at,
    is_active         = true
  returning id into new_id;

  -- Bersihkan duplikat lama: untuk user ini, jika ada row lain dengan
  -- brand+model sama tapi install_id berbeda (sisa UUID lama), hapus yang
  -- paling lama. Ini migrasi otomatis dari UUID random → ANDROID_ID.
  delete from public.user_devices
  where user_id = uid
    and lower(brand) = lower(p_brand)
    and lower(model) = lower(p_model)
    and install_id != coalesce(nullif(p_install_id,''), 'unknown')
    and id != coalesce(new_id, '00000000-0000-0000-0000-000000000000'::uuid);
end;
$fn$;

grant execute on function public.upsert_device(text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.upsert_device(text,text,text,text,text,text,text) to authenticated;
