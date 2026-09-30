-- ============================================================
-- `admin_list_deleted`: kembalikan total TERPISAH (arsip vs pending).
--
-- MASALAH: RPC hanya mengirim `total` = gabungan arsip + anon-pending.
-- Tab "Terhapus" karena itu tidak bisa menampilkan angka arsip dan anon
-- secara terpisah — padahal keduanya sangat berbeda maknanya:
--   - arsip   = user yang SUDAH terhapus permanen (riwayat/audit)
--   - pending = user anon yang MASIH ADA, cuma belum didaftarkan
--
-- BUKTI (produksi 2026-10-02):
--   deleted_users ~1782, anon pending ~101
-- UI hanya menampilkan satu angka gabungan, sehingga 1782 arsip tampak
-- seperti "user terhapus" yang jumlahnya tidak wajar.
--
-- FIX: tambah `total_archive` & `total_pending` di samping `total`.
-- Perubahan aditif — `total` tetap ada supaya klien lama tidak rusak.
--
-- Dasar = definisi live 20260926050000 (urutan paginasi + device_count/
-- location_count dipertahankan).
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
    -- `total` = yang benar-benar ditampilkan (pending dihitung hanya bila
    -- diminta) — dijaga agar paginasi klien lama tetap konsisten.
    'total', v_archive + case when p_include_pending then v_pending else 0 end,
    -- Rincian eksplisit supaya UI bisa memberi label yang benar.
    'total_archive', v_archive,
    'total_pending', v_pending,
    'items', coalesce((
      select jsonb_agg(sub.obj order by sub.sort_at desc nulls last)
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
          -- Urut memakai last_seen agar anon terbaru tampil di atas.
          p.last_seen as sort_at
        from public.profiles p
        where p_include_pending
          and coalesce(p.is_registered, false) = false
          and not exists (
            select 1 from public.dummy_accounts d where d.uid = p.id
          )
        -- PENTING: urutkan SEBELUM limit/offset, kalau tidak halaman 2+
        -- mengambil baris acak (bug paginasi).
        order by sort_at desc nulls last
      ) sub
      limit greatest(p_limit, 1) offset greatest(p_offset, 0)
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$fn$;

revoke execute on function public.admin_list_deleted(integer,integer,boolean)
  from public, anon;
grant execute on function public.admin_list_deleted(integer,integer,boolean)
  to authenticated, service_role;
