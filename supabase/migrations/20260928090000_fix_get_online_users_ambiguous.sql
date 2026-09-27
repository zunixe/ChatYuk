-- Fix: RPC get_online_users ambigu → daftar Online kosong/tidak update.
--
-- GEJALA: user yang statusnya 'online' (mis. "agoy") tidak muncul di daftar
-- Pengguna Online, padahal RPC mengembalikannya.
--
-- AKAR MASALAH: ada DUA overload:
--   1) get_online_users(p_limit int)                       -- wrapper lama
--   2) get_online_users(p_country text, p_limit int)       -- utama (privacy)
-- Client memanggil `.rpc('get_online_users', params: {'p_limit': 200})`.
-- PostgREST tak bisa memilih kandidat (keduanya kompatibel dengan p_limit)
-- → PGRST203 "Could not choose the best candidate function" → RPC GAGAL.
-- Akibat: jatuh ke fallback presence_for yang HANYA memuat user ber-socket,
-- sehingga user yang online tetapi socket-nya belum ter-track (mis. baru
-- buka app / device lain) HILANG dari daftar.
--
-- FIX: hapus wrapper (int) — panggilan `{p_limit}` otomatis cocok ke fungsi
-- utama karena `p_country` punya DEFAULT NULL. Grant ke fungsi utama tetap.

drop function if exists public.get_online_users(int);

-- Pastikan grant fungsi utama (2-arg) tetap ada untuk authenticated & anon.
grant execute on function public.get_online_users(text, int) to authenticated, anon;
