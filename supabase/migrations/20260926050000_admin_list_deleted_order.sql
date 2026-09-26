-- admin_list_deleted: betulkan urutan paginasi.
--
-- BUG: LIMIT/OFFSET diterapkan pada subquery union TANPA ORDER BY di
-- dalamnya — ORDER BY sort_at baru ada di agregasi luar (jsonb_agg).
-- Postgres bebas mengambil baris acak sebelum limit, sehingga halaman 2+
-- berisi baris duplikat/loncat saat data banyak (di skala kecil tidak
-- terlihat karena 1 halaman memuat semua).
--
-- FIX: tambah `order by sub.sort_at desc nulls last` DI DALAM subquery
-- sebelum LIMIT/OFFSET. Output halaman-1 identik (agregat luar tetap
-- mengurutkan ulang), halaman 2+ kini deterministik.
-- Dasar = definisi live 20260926000000 (device_count/location_count dipertahankan).
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
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (
      select count(*) from public.deleted_users
    ) + case when p_include_pending then (
      -- Anon yang belum dihapus & bukan dummy = "pending" (nickname masih
      -- terpakai, bisa dibebaskan admin).
      select count(*) from public.profiles p
       where coalesce(p.is_registered, false) = false
         and not exists (
           select 1 from public.dummy_accounts d where d.uid = p.id
         )
    ) else 0 end,
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
