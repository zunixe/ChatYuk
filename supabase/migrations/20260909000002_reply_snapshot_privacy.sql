-- ============================================================
-- PRIVASI: replied_to_text snapshot isi pesan yang sudah dihapus
--
-- Masalah: saat A me-reply pesan B, snapshot teks tersimpan di kolom
-- replied_to_text milik row A. Kalau B menghapus pesannya, snapshot
-- itu TETAP berisi isi asli di DB — client sudah meredam tampilan,
-- tapi data masih ada (dan bisa bocor via fetch lama/cache basi).
--
-- Fix (server-side, idempotent):
--   1. Trigger: ketika pesan di-update is_deleted=true, kosongkan
--      replied_to_text/replied_to_sender_name di SEMUA row yang
--      me-reply pesan tsb (kedua tabel: private_messages & messages).
--   2. Backfill one-shot: bersihkan snapshot yang menunjuk pesan
--      yang SUDAH terhapus (ada di DB sekarang).
--   3. fromMap client sudah mem-blok tampilan — ini lapis kedua.
-- ============================================================

-- 1a. Trigger untuk private_messages
create or replace function public.scrub_reply_snapshot_private()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_deleted = true and (old.is_deleted is distinct from true) then
    update public.private_messages pm
    set replied_to_text = null,
        replied_to_sender_name = null
    where pm.replied_to_id = new.id;
  end if;
  return new;
end; $$;

drop trigger if exists scrub_reply_snapshot_private_trg on public.private_messages;
create trigger scrub_reply_snapshot_private_trg
after update on public.private_messages
for each row execute function public.scrub_reply_snapshot_private();

-- 1b. Trigger untuk messages (room)
create or replace function public.scrub_reply_snapshot_room()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_deleted = true and (old.is_deleted is distinct from true) then
    update public.messages m
    set replied_to_text = null,
        replied_to_sender_name = null
    where m.replied_to_id = new.id;
  end if;
  return new;
end; $$;

drop trigger if exists scrub_reply_snapshot_room_trg on public.messages;
create trigger scrub_reply_snapshot_room_trg
after update on public.messages
for each row execute function public.scrub_reply_snapshot_room();

-- 2. Backfill: snapshot yang menunjuk pesan sudah-terhapus (one-shot)
update public.private_messages pm
set replied_to_text = null,
    replied_to_sender_name = null
where pm.replied_to_id is not null
  and exists (
    select 1 from public.private_messages src
    where src.id::text = pm.replied_to_id and src.is_deleted = true
  );

update public.messages m
set replied_to_text = null,
    replied_to_sender_name = null
where m.replied_to_id is not null
  and exists (
    select 1 from public.messages src
    where src.id = m.replied_to_id and src.is_deleted = true
  );
