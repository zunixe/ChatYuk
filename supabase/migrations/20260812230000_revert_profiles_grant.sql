-- ============================================================
-- ChatYuk: Revert hardening profiles column-level revoke
-- Column-level REVOKE SELECT pada profiles mematahkan upsert
-- registerProfile() — PostgREST butuh SELECT pada kolom yang
-- di-upsert (termasuk ip_address & fcm_token), sehingga user baru
-- gagal daftar ("permission denied for table profiles", 42501).
--
-- Keamanan kolom sensitif tetap terjaga di level APP: semua query
-- profiles sudah exclude ip_address & fcm_token (auth_service.dart,
-- chat_service.dart). Column-level grant tidak memberi proteksi nyata
-- dan merusak fungsionalitas → dikembalikan ke grant penuh.
-- ============================================================

grant select on public.profiles to anon, authenticated;
