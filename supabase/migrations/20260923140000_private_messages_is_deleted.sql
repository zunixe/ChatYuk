-- Sinkron repo ↔ DB live: kolom private_messages.is_deleted.
-- Kolom SUDAH ADA di live (delete private chat memakainya), tapi tidak ada
-- file migrasi yang membuatnya — fresh DB/CI akan gagal saat update
-- is_deleted. Idempoten; tidak menyentuh fungsi FROZEN/RLS.
alter table public.private_messages
  add column if not exists is_deleted boolean not null default false;
