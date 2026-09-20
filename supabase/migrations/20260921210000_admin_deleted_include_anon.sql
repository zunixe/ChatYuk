-- Tab "Terhapus": tampilkan user terhapus (arsip) DAN user anon yang belum
-- dihapus dalam satu daftar, plus admin bisa menghapus user anon itu supaya
-- NICKNAME-nya bebas dipakai orang lain.
--
-- Latar: `claim_nickname` sudah bisa mengambil nickname anon yang idle > 7
-- hari, tapi tidak ada tombol admin untuk menghapus anon yang masih "aktif"
-- (last_seen baru) padahal jelas sampah (nickname uji coba). Akibatnya
-- nickname tertahan sampai 7 hari.
--
-- Yang ditambahkan:
--   1. `admin_delete_anon_user(p_uid)` — hapus 1 user anon (arsip dulu ke
--      deleted_users, alasan 'admin_delete'), aman dari FK. Menolak user
--      terdaftar (registered) & dummy.
--   2. `admin_list_deleted` diperluas: `p_include_pending=true` menambahkan
--      user ANON yang belum dihapus sebagai item `pending` (nickname masih
--      terpakai). Item pending punya `pending=true` + `deleted_at=null`.
--
-- CATATAN: `admin_list_deleted` TIDAK frozen. `nearby_users`/`admin_stats_detail`
-- tidak disentuh.

-- ── 1. Hapus user ANON oleh admin (bebaskan nickname segera) ──
create or replace function public.admin_delete_anon_user(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_is_reg boolean;
  v_is_dummy boolean;
  v_nick text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(p.is_registered, false), coalesce(p.nickname, '')
    into v_is_reg, v_nick
    from public.profiles p
   where p.id = p_uid;

  if v_nick = '' and not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  -- Cek DUMMY lebih dulu: dummy bisa `is_registered=true` (dibuat admin),
  -- sehingga tanpa urutan ini ia tertangkap sebagai REGISTERED dan pesan
  -- yang muncul menyesatkan ("akun terdaftar" padahal dummy).
  select exists(select 1 from public.dummy_accounts d where d.uid = p_uid)
    into v_is_dummy;
  if v_is_dummy then
    return jsonb_build_object('ok', false, 'error', 'DUMMY');
  end if;

  -- Jangan hapus akun terdaftar (punya email) lewat jalur ini — pakai
  -- mekanisme akun lain supaya tidak menghapus data user sungguhan.
  if v_is_reg then
    return jsonb_build_object('ok', false, 'error', 'REGISTERED');
  end if;

  -- Arsip dulu (snapshot nickname/brand/model/ip) — alasan 'admin_delete'.
  perform public.fn_archive_deleted_user(p_uid, 'admin_delete');

  -- Cascade bersih-bersih. Sebagian FK CASCADE, tapi tabel yang SET NULL /
  -- tanpa FK dibersihkan manual supaya tidak ada sisa jejak.
  delete from public.room_presence where user_id = p_uid;
  delete from public.blocks where blocker_id = p_uid or blocked_id = p_uid;
  delete from public.reports where reporter_id = p_uid or reported_id = p_uid;
  delete from public.user_photos where user_id = p_uid;
  delete from public.user_devices where user_id = p_uid;
  delete from public.user_location_history where user_id = p_uid;
  delete from public.contact_messages where user_id = p_uid;

  -- Chat privat yang melibatkan user ini (pesan + chat).
  delete from public.private_messages pm
   using public.private_chats pc
   where pm.chat_id = pc.chat_id
     and pc.participants @> array[p_uid]::uuid[];
  delete from public.private_chats pc
   where pc.participants @> array[p_uid]::uuid[];

  delete from public.profiles where id = p_uid;

  -- coin_ledger = append-only (trigger `coin_ledger_no_delete`). Menghapus
  -- auth.users memicu cascade ke coin_ledger → trigger menolak. Matikan
  -- sementara (pola sama dengan admin_delete_dummy).
  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from auth.users where id = p_uid;

  -- Ringkasan admin langsung segar.
  delete from public.admin_stats_cache where id = 1;

  return jsonb_build_object('ok', true, 'nickname', v_nick);
end;
$fn$;

revoke execute on function public.admin_delete_anon_user(uuid) from public, anon;
grant execute on function public.admin_delete_anon_user(uuid) to authenticated, service_role;

-- ── 2. admin_list_deleted: sertakan user anon yang BELUM dihapus ──
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
            'pending', false
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
            'city', p.city
          ) as obj,
          -- Urut memakai last_seen agar anon terbaru tampil di atas.
          p.last_seen as sort_at
        from public.profiles p
        where p_include_pending
          and coalesce(p.is_registered, false) = false
          and not exists (
            select 1 from public.dummy_accounts d where d.uid = p.id
          )
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

-- Signature lama (2-arg) dibuang agar tidak ada overload ambigu.
drop function if exists public.admin_list_deleted(integer,integer);
