-- Device identifier BARU: MediaDrm (Widevine) deviceUniqueId → `drm-<hex>`.
--
-- Kenapa: `install_id` lama = `android-<ANDROID_ID>`, dan Android 8+
-- meng-scope ANDROID_ID ke (device + user profile + app signing key) →
-- berubah saat ganti keystore / Dual Apps / Second Space, sehingga device
-- yang sama tampil sebagai device BARU (device ter-exclude "muncul lagi").
-- MediaDrm deviceUniqueId stabil per perangkat FISIK (tahan reinstall,
-- ganti signing key, dan beda user profile).
--
-- MASALAH TRANSISI: device lama sudah punya baris `android-<id>`. Setelah
-- update app, install_id jadi `drm-<id>` → akan INSERT baris baru
-- (duplikat 1 HP = 2 baris). Solusi: parameter `p_legacy_install_id` untuk
-- MIGRASI in-place baris lama milik user yang sama.
--
-- CATATAN SIGNATURE: versi lama punya 7-arg dan 8-arg (overload). Keduanya
-- DIBUANG dulu supaya tidak ada overload ambigu; hanya tersisa 9-arg.
-- Perilaku `nickname_snapshot` (dari versi 8-arg) DIPERTAHANKAN.
--
-- `admin_stats_detail` FROZEN — tidak disentuh (ia memakai uid, bukan
-- install_id, jadi tidak terpengaruh).

drop function if exists public.upsert_device(
  text, text, text, text, text, text, text);
drop function if exists public.upsert_device(
  text, text, text, text, text, text, text, text);

create or replace function public.upsert_device(
  p_install_id text,
  p_brand text,
  p_model text,
  p_os_name text,
  p_os_version text,
  p_app_version text,
  p_ip text,
  p_nickname text default '',
  p_legacy_install_id text default ''
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
    -- Bila baris `v_new` sudah ada untuk user ini, buang baris legacy
    -- (hindari PK conflict `(user_id, install_id)`).
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
     ip_address, nickname_snapshot, last_seen_at, is_active)
  values
    (uid, v_new, p_brand, p_model, p_os_name, p_os_version, p_app_version,
     p_ip, nullif(p_nickname, ''), now(), true)
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
    is_active         = true
  returning id into new_id;

  -- Bersihkan duplikat lama: baris lain milik user ini dengan brand+model
  -- sama tapi install_id berbeda (sisa identifier lama). Pertahankan baris
  -- yang baru saja ditulis.
  delete from public.user_devices
  where user_id = uid
    and lower(brand) = lower(p_brand)
    and lower(model) = lower(p_model)
    and install_id != v_new
    and id != coalesce(new_id, '00000000-0000-0000-0000-000000000000'::uuid);
end;
$fn$;

revoke execute on function public.upsert_device(
  text,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.upsert_device(
  text,text,text,text,text,text,text,text,text) to authenticated, service_role;
