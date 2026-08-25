-- Toggle admin: tampilkan tombol call ke SEMUA user (termasuk anon/guest).
-- Default false = perilaku lama (hanya user terdaftar).
alter table public.app_settings
  add column if not exists call_all_enabled boolean not null default false;
