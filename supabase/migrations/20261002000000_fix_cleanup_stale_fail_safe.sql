-- ============================================================
-- FIX KRITIS `cleanup_stale_anonymous`: LOGIKA SELEKSI TERBALIK
-- menghapus user yang TIDAK terbukti stale (fail-open → mass delete).
--
-- BUKTI (produksi, 2026-10-02 via Management API):
--   select reason, count(*) from public.deleted_users group by reason;
--     stale_cleanup   1671   (94% dari seluruh arsip)
--     admin_delete      87
--     self_delete       18
--     nickname_claim     6
--   dari 1671 stale_cleanup: 1646 (98.5%) diarsipkan dengan
--   last_seen_at NULL + created_at NULL + nickname '' (tanpa profil).
--
-- KRONOLOGI (cron.job_run_details jobid 1):
--   24–28 Sep 04:00 → FAILED 'coin_ledger is append-only' (5 hari!)
--   29–30 Sep       → succeeded (setelah 20260929000000)
--   28 Sep 23:00    → 1594 terhapus DALAM SATU JAM (= run manual, sapuan
--                     pertama setelah fix, akumulasi 5 hari lepas sekaligus)
--
-- AKAR BUG (fungsi lama):
--   and not exists (
--     select 1 from public.profiles p
--     where p.id = u.id
--       and p.last_seen > now() - make_interval(days => min_age_days)
--   )
--
--   Ini menyeleksi: "user yang TIDAK PUNYA baris profil dengan last_seen BARU".
--   Konsekuensi:
--     (a) user yang baris `profiles`-nya TIDAK ADA → langsung lolos → dihapus
--         meski statusnya tidak diketahui (inilah 1646 "user hantu");
--     (b) user dengan `last_seen IS NULL` → predikat `NULL > ts` = NULL
--         (bukan true) → NOT EXISTS true → lolos → ikut dihapus padahal
--         tidak ada bukti sama sekali ia inactive.
--   Pola `NOT EXISTS(<predikat positif>)` = FAIL-OPEN: ketiadaan data
--   diperlakukan sebagai bukti. Untuk operasi destruktif ini salah total.
--
-- PERBAIKAN: FAIL-SAFE. Hapus HANYA bila ada bukti umur ≥ min_age_days.
--   umur = coalesce(last_seen, created_at, auth.users.created_at)
--   - last_seen tersedia  → pakai itu;
--   - last_seen NULL      → fallback created_at profil;
--   - keduanya NULL       → fallback auth.users.created_at;
--   - SEMUANYA NULL       → JANGAN hapus (data tidak cukup untuk memutuskan).
--
--   Perubahan kunci: `last_seen` NULL tidak lagi berarti "stale", melainkan
--   "tidak diketahui" → DIPERTAHANKAN. Ini menghentikan penghapusan massal.
--
-- DAMPAK: cleanup jadi jauh lebih konservatif (benar). Akun anon yang benar
--   -benar idle > 7 hari (punya last_seen) tetap dibersihkan seperti biasa.
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
  -- Hanya user anon yang TERBUKTI idle >= min_age_days.
  -- Semua jalur data (last_seen / profil.created_at / auth.created_at)
  -- dipakai; bila tak satu pun tersedia, user TIDAK dihapus (fail-safe).
  for r in
    select u.id
    from auth.users u
    left join public.profiles p on p.id = u.id
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.dummy_accounts d where d.uid = u.id
      )
      and coalesce(
            p.last_seen,
            p.created_at,
            u.created_at
          ) is not null
      and coalesce(
            p.last_seen,
            p.created_at,
            u.created_at
          ) < now() - make_interval(days => min_age_days)
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

-- Verifikasi setelah apply (harus 0 atau kecil, BUKAN ribuan):
--   1) Dry-run: berapa yang AKAN dihapus dengan aturan baru?
--      select count(*) from auth.users u
--        left join public.profiles p on p.id = u.id
--       where u.is_anonymous and u.email is null
--         and not exists (select 1 from public.dummy_accounts d where d.uid=u.id)
--         and coalesce(p.last_seen,p.created_at,u.created_at) is not null
--         and coalesce(p.last_seen,p.created_at,u.created_at) < now() - interval '7 days';
--   2) Pastikan user anon yang masih ada TIDAK lagi terhapus:
--      select count(*) from public.profiles where last_seen is null;
