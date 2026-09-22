-- app_update_config: setelan popup update aplikasi (Play In-App Update).
--
-- Sumber kebijakan di-refresh: klien membaca kolom ini saat masuk app dan
-- membandingkan versionName lokal (X.Y.Z) dengan latest_version. Bila
-- versi lokal < min_version → popup wajib (force, tanpa tombol Nanti).
--
-- update_enabled = false (default) supaya fitur aman dirilis sebelum admin
-- mengisi nilainya. Tidak ada DROP/ALTER TYPE → tidak perlu penanda -- SAFE.
-- Tidak menyentuh fungsi FROZEN.
alter table public.app_settings
  add column if not exists update_enabled boolean not null default false,
  add column if not exists latest_version text not null default '',
  add column if not exists min_version    text not null default '',
  add column if not exists update_notes   text not null default '';
