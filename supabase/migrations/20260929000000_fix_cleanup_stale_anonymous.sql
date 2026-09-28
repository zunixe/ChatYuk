-- ============================================================
-- FIX `cleanup_stale_anonymous`: gagal total karena 2 defect
-- (terbukti di log 2026-09-29, direproduksi via Management API).
--
-- GEJALA: log Postgres `P0001 coin_ledger is append-only` berulang,
-- 1.597 akun anon stale MENUMPUK (cleanup tidak pernah berhasil membersihkan).
--
-- AKAR (dua bug di fungsi lama):
--   1. `delete from auth.users` memicu cascade FK ke `coin_ledger`
--      (coin_ledger_user_id_fkey ON DELETE CASCADE) — tetapi trigger
--      `coin_ledger_no_delete` (append-only) menolak cascade itu →
--      "coin_ledger is append-only". (delete_my_account & admin_delete_anon_user
--      sudah menangani ini: hapus coin_ledger eksplisit + matikan trigger /
--      session_replication_role.)
--   2. `delete from public.profiles` dijalankan SEBELUM
--      user_devices/user_location_history dihapus. FK-nya SET NULL tapi kolom
--      NOT NULL → 23503. (delete_my_account sudah hapus keduanya lebih dulu.)
--   3. Loop TANPA `exception` per-user → SATU user bermasalah membatalkan
--      SELURUH cleanup (transaksi), itulah kenapa akun stale menumpuk.
--
-- PERBAIKAN: ikut pola `delete_my_account` yang sudah terverifikasi —
-- hapus device/location lebih dulu, hapus coin_ledger + point_events dengan
-- trigger dimatikan, baru delete auth.users; tiap user dibungkus
-- `exception` supaya satu kegagalan tidak menggagalkan sisanya.
--
-- Tidak FROZEN (tidak ada di scripts/frozen_functions.txt).
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.cleanup_stale_anonymous(min_age_days integer default 7)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  deleted int := 0;
  r record;
begin
  for r in
    select u.id
    from auth.users u
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.dummy_accounts d where d.uid = u.id
      )
      and not exists (
        select 1 from public.profiles p
        where p.id = u.id
          and p.last_seen > now() - make_interval(days => min_age_days)
      )
  loop
    begin
      perform public.fn_archive_deleted_user(r.id, 'stale_cleanup');
      delete from public.room_presence where user_id = r.id;
      delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
      delete from public.reports where reporter_id = r.id or reported_id = r.id;
      delete from public.user_photos where user_id = r.id;

      delete from public.private_messages pm
      using public.private_chats pc
      where pm.chat_id = pc.chat_id
        and pc.participants @> array[r.id]::uuid[];

      delete from public.private_chats pc
      where pc.participants @> array[r.id]::uuid[];

      delete from public.private_messages where sender_id = r.id;

      -- Device & location WAJIB dihapus SEBELUM profiles (FK SET NULL tapi
      -- kolom NOT NULL → 23503 bila profiles dihapus lebih dulu).
      delete from public.user_devices where user_id = r.id;
      delete from public.user_location_history where user_id = r.id;
      delete from public.contact_messages where user_id = r.id;

      delete from public.profiles where id = r.id;

      -- Ledger koin & point_events: trigger append-only menolak DELETE, dan
      -- cascade dari auth.users pun ditolak → matikan trigger sementara.
      alter table public.coin_ledger disable trigger coin_ledger_no_delete;
      delete from public.coin_ledger where user_id = r.id;
      alter table public.coin_ledger enable trigger coin_ledger_no_delete;

      delete from public.point_events where user_id = r.id;

      delete from auth.users where id = r.id;
      deleted := deleted + 1;
    exception when others then
      -- Satu user gagal (mis. data aneh) tidak boleh menggagalkan seluruh
      -- cleanup — lanjut ke user berikutnya.
      null;
    end;
  end loop;
  return deleted;
end;
$function$;

-- Verifikasi (harus mengembalikan jumlah > 0, tanpa error 'append-only'):
--   select public.cleanup_stale_anonymous(7);
