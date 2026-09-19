-- Lanjutan 20260921170000: UN-exclude device harus ikut membersihkan
-- `excluded_uids` yang dihasilkan cascade — kalau tidak, device yang dihapus
-- dari daftar exclude tetap tersembunyi karena uid-nya masih ada di
-- excluded_uids (user "tidak muncul kembali" setelah di-unexclude).
--
-- Aturan: saat `admin_set_excluded_devices`, uid yang TIDAK lagi terkait
-- device mana pun yang ter-exclude DAN bukan uid manual (ditambah langsung
-- oleh admin lewat daftar uid) akan dibuang dari excluded_uids.
--
-- Bagaimana membedakan uid manual vs uid hasil cascade? Tidak perlu:
--   * uid yang masih terkait device ter-exclude → pertahankan.
--   * uid yang TIDAK punya device di excluded_devices DAN tidak punya baris
--     user_devices sama sekali → pertahankan (itu uid manual, mis. anon tanpa
--     device).
--   * sisanya (punya device, tapi device-nya tidak lagi ter-exclude) → buang.
-- Jadi anon tanpa baris device yang ditambahkan manual tetap aman.

create or replace function public.admin_set_excluded_devices(p_list jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $fn$
declare
  v_clean jsonb;
  v_uids  jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_list is null or jsonb_typeof(p_list) <> 'array' then
    raise exception 'p_list must be a JSON array';
  end if;

  -- Bersihkan daftar device: text non-kosong, trim, unik.
  select coalesce(jsonb_agg(distinct t), '[]'::jsonb) into v_clean
    from jsonb_array_elements_text(p_list) as t
    where nullif(trim(t), '') is not null;

  -- Sinkronkan excluded_uids dengan daftar device yang BARU:
  --   * uid lama yang device-nya MASIH ter-exclude → pertahankan (cascade
  --     tetap berlaku walau install_id berubah).
  --   * uid yang TIDAK punya baris device sama sekali → pertahankan (uid
  --     manual, mis. anon tanpa device).
  --   * uid yang punya device tapi device-nya tidak lagi ter-exclude → buang.
  select coalesce(jsonb_agg(distinct u), '[]'::jsonb) into v_uids
    from (
      select jsonb_array_elements_text(
               case when jsonb_typeof(excluded_uids) = 'array'
                    then excluded_uids else '[]'::jsonb end) as u
        from public.app_settings where id = 'global'
    ) s
   where u ~* '^[0-9a-f-]{36}$'
     and (
       exists (
         select 1 from public.user_devices d
          where d.user_id::text = u
            and d.install_id in (
              select jsonb_array_elements_text(v_clean)
            )
       )
       or not exists (
         select 1 from public.user_devices d
          where d.user_id::text = u
       )
     );

  update public.app_settings
     set excluded_devices = coalesce(v_clean, '[]'::jsonb),
         excluded_uids    = coalesce(v_uids, '[]'::jsonb),
         updated_at       = now()
   where id = 'global';

  -- Ringkasan langsung segar (WHERE wajib: safeupdate menolak DELETE tanpa WHERE).
  delete from public.admin_stats_cache where id = 1;

  return coalesce(v_clean, '[]'::jsonb);
end;
$fn$;

revoke execute on function public.admin_set_excluded_devices(jsonb)
  from public, anon;
grant execute on function public.admin_set_excluded_devices(jsonb)
  to authenticated, service_role;
