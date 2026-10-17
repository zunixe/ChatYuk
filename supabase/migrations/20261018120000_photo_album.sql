-- Album foto (bundle multi-foto ala WhatsApp).
--
-- Satu batch kirim (mis. 3 foto sekaligus) = satu `album_id` (UUID) yang
-- dipakai bersama oleh semua pesan foto batch tersebut. Klien mengelompokkan
-- pesan berurutan dengan `album_id` sama menjadi SATU bubble grid.
--
-- ADITIF & nullable: pesan lama `album_id IS NULL` → perilaku lama persis
-- (1 pesan = 1 bubble foto), jadi tidak ada regresi.

alter table public.private_messages
  add column if not exists album_id uuid;

alter table public.messages
  add column if not exists album_id uuid;

-- Index parsial: hanya baris ber-album (mayoritas pesan bukan album).
create index if not exists idx_pm_album
  on public.private_messages (album_id)
  where album_id is not null;

create index if not exists idx_m_album
  on public.messages (album_id)
  where album_id is not null;
