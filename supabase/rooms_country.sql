-- ============================================
-- ChatYuk: Room per Negara
-- Tambah country/category, migrasi room lama ke Indonesia,
-- update referensi messages & room_presence.
-- Jalankan di: Supabase Dashboard > SQL Editor
-- ============================================

-- Lepas FK sementara agar bisa update id room
alter table public.messages drop constraint if exists messages_room_id_fkey;
alter table public.room_presence drop constraint if exists room_presence_room_id_fkey;

-- Kolom baru
alter table public.rooms add column if not exists country text not null default '';
alter table public.rooms add column if not exists category text not null default '';

-- Room lama dianggap milik Indonesia: category = id lama, id jadi 'Indonesia_<category>'
update public.rooms set category = id, country = 'Indonesia' where id not like 'Indonesia_%';
update public.messages set room_id = 'Indonesia_' || room_id where room_id not like 'Indonesia_%';
update public.room_presence set room_id = 'Indonesia_' || room_id where room_id not like 'Indonesia_%';
update public.rooms set id = 'Indonesia_' || id where id not like 'Indonesia_%';

-- Index untuk country
create index if not exists rooms_country_idx on public.rooms (country);

-- Pasang kembali FK
alter table public.messages add constraint messages_room_id_fkey
  foreign key (room_id) references public.rooms (id) on delete cascade;
alter table public.room_presence add constraint room_presence_room_id_fkey
  foreign key (room_id) references public.rooms (id) on delete cascade;