-- ============================================================
-- Langkah 1 (a): helper TERPUSAT user_fcm_tokens(uuid)
--
-- Masalah: beberapa trigger notif membaca `profiles.fcm_token` SAJA
-- (legacy, sudah dikosongkan migrasi 20260827000000). Akibatnya notif
-- TIDAK terkirim ke device klien baru yang terdaftar di `user_devices`.
--
-- Helper ini mengembalikan SEMUA token aktif:
--   - utama: `user_devices.fcm_token` (per perangkat, sumber baru)
--   - fallback: `profiles.fcm_token` HANYA bila user tidak punya device
--     aktif bertoken (kompat klien lama).
--
-- SECURITY DEFINER + set search_path (aman dipanggil dari trigger).
-- Read-only, tidak mengubah tabel. Additive → tidak menyentuh apa pun.
-- ============================================================

create or replace function public.user_fcm_tokens(p_uid uuid)
returns setof text
language sql
security definer
set search_path to 'public'
as $$
  with dev as (
    select d.fcm_token
      from public.user_devices d
     where d.user_id = p_uid
       and d.is_active = true
       and coalesce(d.fcm_token,'') <> ''
  )
  select fcm_token from dev
  union
  select coalesce(p.fcm_token,'')
    from public.profiles p
   where p.id = p_uid
     and coalesce(p.fcm_token,'') <> ''
     and not exists (select 1 from dev);
$$;

revoke execute on function public.user_fcm_tokens(uuid) from public, anon;
grant execute on function public.user_fcm_tokens(uuid) to authenticated, service_role;

-- Verifikasi:
--   select proname from pg_proc where proname='user_fcm_tokens';
--   select * from public.user_fcm_tokens('<uid dummy tanpa device>');  -- [] (aman)
