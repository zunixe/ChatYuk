-- ============================================================
-- FIX KRITIS `admin_list_deleted`: `p_limit` / `p_offset` DIABAIKAN.
--
-- BUKTI (produksi 2026-10-02, via Management API):
--   select jsonb_array_length(public.admin_list_deleted(5,0,true)->'items');
--     -> 1883   (HARUSNYA 5)
--   select jsonb_array_length(public.admin_list_deleted(100,0,true)->'items');
--     -> 1883   (HARUSNYA 100)
--
-- Ini menjelaskan keluhan "tab Terhapus isinya banyak banget": aplikasi
-- meminta 100 baris per halaman, server mengirim SELURUH baris —
-- tiap refresh, tiap polling 30 detik. Boros bandwidth + memori, dan
-- `deletedHasMore` jadi salah hitung.
--
-- AKAR: LIMIT/OFFSET diletakkan DI DALAM subquery `sub` yang kemudian
-- diagregasi oleh `jsonb_agg(...)` pada query LUAR. LIMIT di subquery itu
-- tidak membatasi jumlah baris yang diagregasi di level luar, sehingga
-- seluruh himpunan ikut ter-agregasi. (Bug tetap ada meski ORDER BY sudah
-- dipindah ke dalam subquery pada 20260926050000 — yang diperbaiki saat
-- itu hanya urutan, bukan pemotongan.)
--
-- FIX: potong hasil (ORDER BY + LIMIT + OFFSET) di satu subquery bernama
-- `page`, BARU diagregasi di query luar. Dengan begitu jumlah item yang
-- dikembalikan tepat sebanyak `p_limit`.
--
-- Sekaligus mempertahankan `total_archive` / `total_pending` (dari
-- 20261002010000) supaya chip filter bisa berlabel benar.
--
-- Tidak FROZEN (tidak ada di scripts/frozen_functions.txt).
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.admin_list_deleted(
  p_limit integer default 100,
  p_offset integer default 0,
  p_include_pending boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_archive int;
  v_pending int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select count(*) into v_archive from public.deleted_users;

  select count(*) into v_pending
    from public.profiles p
   where coalesce(p.is_registered, false) = false
     and not exists (
       select 1 from public.dummy_accounts d where d.uid = p.id
     );

  select jsonb_build_object(
    'total', v_archive + case when p_include_pending then v_pending else 0 end,
    'total_archive', v_archive,
    'total_pending', v_pending,
    -- PENTING: `page` SUDAH dipotong ORDER BY + LIMIT + OFFSET, baru
    -- diagregasi. Sebelumnya LIMIT berada di dalam subquery yang diagregasi
    -- sehingga tidak berefek (seluruh baris ikut terkirim).
    'items', coalesce((
      select jsonb_agg(page.obj order by page.sort_at desc nulls last)
      from (
        select sub.obj, sub.sort_at
        from (
          -- (a) Arsip user terhapus.
          select
            jsonb_build_object(
              'user_id', d.user_id,
              'nickname', d.nickname,
              'email', d.email,
              'is_registered', d.is_registered,
              'brand', d.brand,
              'model', d.model,
              'ip_address', d.ip_address,
              'last_seen_at', d.last_seen_at,
              'created_at', d.created_at,
              'deleted_at', d.deleted_at,
              'reason', d.reason,
              'claimed_by', d.claimed_by,
              'claimed_nick', d.claimed_nick,
              'pending', false,
              'device_count', coalesce(jsonb_array_length(d.devices), 0),
              'location_count', coalesce(jsonb_array_length(d.locations), 0)
            ) as obj,
            d.deleted_at as sort_at
          from public.deleted_users d

          union all

          -- (b) Anon belum dihapus (pending) — hanya bila diminta.
          select
            jsonb_build_object(
              'user_id', p.id,
              'nickname', p.nickname,
              'email', p.email,
              'is_registered', coalesce(p.is_registered, false),
              'brand', '',
              'model', '',
              'ip_address', coalesce(p.ip_address, ''),
              'last_seen_at', p.last_seen,
              'created_at', p.created_at,
              'deleted_at', null,
              'reason', 'pending_anon',
              'claimed_by', null,
              'claimed_nick', null,
              'pending', true,
              'status', p.status,
              'country', p.country,
              'city', p.city,
              'device_count', 0,
              'location_count', 0
            ) as obj,
            p.last_seen as sort_at
          from public.profiles p
          where p_include_pending
            and coalesce(p.is_registered, false) = false
            and not exists (
              select 1 from public.dummy_accounts d where d.uid = p.id
            )
        ) sub
        -- Urutkan & potong DI LEVEL INI (bukan di dalam agregasi).
        order by sub.sort_at desc nulls last
        limit greatest(p_limit, 1)
        offset greatest(p_offset, 0)
      ) page
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_list_deleted(integer,integer,boolean)
  from public, anon;
grant execute on function public.admin_list_deleted(integer,integer,boolean)
  to authenticated, service_role;

-- Verifikasi setelah apply (harus tepat sesuai limit):
--   select jsonb_array_length(public.admin_list_deleted(5,0,true)->'items');   -- 5
--   select jsonb_array_length(public.admin_list_deleted(100,0,true)->'items'); -- 100
--   -- halaman 2 tidak boleh beririsan dengan halaman 1:
--   select public.admin_list_deleted(5,0,true)->'items'->0->>'user_id'
--        = public.admin_list_deleted(5,5,true)->'items'->0->>'user_id';       -- false
