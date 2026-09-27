-- ============================================================
-- Selaraskan drift: GRANT SELECT tabel-level pada public.rooms
--
-- Latar: saat fresh-replay, `20260814170000_private_rooms.sql` melakukan
-- `revoke select on public.rooms` lalu `grant select (kolom...)` — hanya 13
-- kolom lama. Belakangan `rooms` bertambah kolom (live_uid, max_members,
-- approval_required, muted_by, dll) TANPA memperbarui daftar grant kolom.
-- Di PROD, `rooms` punya GRANT SELECT level-TABEL (21/21 kolom) — jadi query
-- yang menyertakan kolom baru tetap jalan. Di lokal tidak → error
-- "permission denied for table rooms" (42501).
--
-- Migration ini menyamakan lokal dengan prod. RLS policy `rooms_select`
-- tetap menjadi penyaring baris; grant hanya membuka izin kolom.
-- Idempotent.
-- ============================================================

grant select on table public.rooms to anon, authenticated;
