-- ============================================================
-- ChatYuk: Fitur Invisible untuk Admin (zunixe@gmail.com)
-- Toggle invisible → admin tidak muncul di daftar online.
-- ============================================================

alter table public.app_settings
  add column if not exists invisible_enabled boolean not null default false;

-- status 'invisible' untuk admin — perlu diizinkan oleh CHECK constraint profiles
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check
  check (status = ANY (ARRAY['online'::text, 'idle'::text, 'offline'::text, 'invisible'::text]));
