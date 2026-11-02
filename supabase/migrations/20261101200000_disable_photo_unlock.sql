-- ============================================================
-- 20261101190000_disable_photo_unlock.sql
-- Fitur "buka foto pakai koin" DINONAKTIFKAN (keputusan produk 2026-11-01).
--
-- Server `unlock_photo` sudah benar & ter-grant, tetapi TIDAK ADA UI yang
-- memanggilnya — dan `user_info_build.dart` justru membuang foto terkunci.
-- Akibatnya `photo_income` tidak pernah bisa terjadi, dan admin masih bisa
-- mengubah harga yang tidak berefek.
--
-- Perbaikan:
--   1. Cabut EXECUTE dari authenticated (service_role tetap, untuk internal).
--   2. Normalkan tipe kolom `photo_unlock_once`/`photo_unlock_perm` ke int.
--      Baseline (20260812101000) membuatnya BOOLEAN sementara semua konsumen
--      memperlakukannya sebagai INT → pada replay bersih (`supabase db reset`)
--      `ADD COLUMN IF NOT EXISTS ... int` menjadi no-op dan fungsi bisa gagal.
--   3. Tabel `photo_unlocks` DIBIARKAN: dipakai penghapusan akun
--      (delete_my_account) dan riwayat akses lama.
-- ============================================================

-- 1. Cabut akses client.
-- SAFE: tidak ada pemanggil client (PointsService.unlockPhoto & wiring UI
-- sudah dihapus). Terdampak: fitur buka foto (dinonaktifkan), penghasilan
-- foto (tidak lagi bisa terjadi — memang sudah tidak terjadi).
REVOKE EXECUTE ON FUNCTION public.unlock_photo(text, text) FROM public, anon, authenticated; -- SAFE: fitur buka foto dinonaktifkan; tidak ada pemanggil client. Terdampak: buka foto (mati), photo_income (mati).
REVOKE EXECUTE ON FUNCTION public.unlock_photo(uuid, text) FROM public, anon, authenticated; -- SAFE: overload lama yang masih menerima bucket bonus; dicabut agar tak ada sisa jalur. Terdampak: sama seperti di atas.

-- 2. Normalkan tipe kolom (boolean → int) agar replay migrasi bersih.
-- SAFE: kolom hanya dibaca fungsi unlock_photo yang sudah dicabut aksesnya;
-- tidak ada konsumen lain. Terdampak: buka foto (mati).
DO $do$
DECLARE
    v_once_type text;
    v_perm_type text;
BEGIN
    SELECT data_type INTO v_once_type
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_settings'
       AND column_name = 'photo_unlock_once';
    SELECT data_type INTO v_perm_type
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_settings'
       AND column_name = 'photo_unlock_perm';

    IF v_once_type = 'boolean' THEN
        -- false → 0, true → 5 (default lama) supaya tidak jadi NULL.
        ALTER TABLE public.app_settings
            ALTER COLUMN photo_unlock_once TYPE integer
            USING (CASE WHEN photo_unlock_once THEN 5 ELSE 0 END); -- SAFE: normalisasi tipe boolean→int; kolom tidak lagi dipakai fitur apa pun.
    END IF;

    IF v_perm_type = 'boolean' THEN
        ALTER TABLE public.app_settings
            ALTER COLUMN photo_unlock_perm TYPE integer
            USING (CASE WHEN photo_unlock_perm THEN 20 ELSE 0 END); -- SAFE: normalisasi tipe boolean→int; kolom tidak lagi dipakai fitur apa pun.
    END IF;
END
$do$;
