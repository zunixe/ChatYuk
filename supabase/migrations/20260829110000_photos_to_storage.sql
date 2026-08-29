-- Migrasi foto base64 → Storage path (massal)
-- Tulis baru hanya ke image_path (Storage), image_data dikosongkan.
-- Baca tetap dual-mode (image_path vs image_data) sampai migrasi bersih.

alter table public.private_messages add column if not exists image_path text default '' not null;
alter table public.messages add column if not exists image_path text default '' not null;
alter table public.private_messages add column if not exists voice_path text default '' not null;
alter table public.messages add column if not exists voice_path text default '' not null;
alter table public.private_messages add column if not exists duration_ms int default 0 not null;
alter table public.messages add column if not exists duration_ms int default 0 not null;

-- Index untuk cari yang masih base64
create index if not exists idx_private_messages_need_migrate on public.private_messages ((image_data like 'data:%')) where image_data like 'data:%';
create index if not exists idx_messages_need_migrate on public.messages ((image_data like 'data:%')) where image_data like 'data:%';

-- Cron: migrasi massal via Edge Function migrate-photos — jadwal via Supabase Dashboard Cron (tiap jam 04:00, POST https://.../functions/v1/migrate-photos)

-- Update send functions to enforce Storage path (jika masih ada yang kirim base64, tolak)
-- Kita keep dual-mode di service, tapi DB trigger bisa kosongkan image_data jika image_path terisi
create or replace function public.enforce_storage_photo()
returns trigger language plpgsql as $$
begin
  if NEW.image_path is not null and NEW.image_path <> '' then
    NEW.image_data := '';
  end if;
  return NEW;
end; $$;

drop trigger if exists enforce_storage_private on public.private_messages;
create trigger enforce_storage_private before insert or update on public.private_messages for each row execute function public.enforce_storage_photo();

drop trigger if exists enforce_storage_room on public.messages;
create trigger enforce_storage_room before insert or update on public.messages for each row execute function public.enforce_storage_photo();
