-- KIRIM KONTAK (a la WhatsApp) — private chat, grup & global room.
--
-- ADITIF (tidak mengubah fungsi FROZEN / policy tabel bersama):
--  1) type 'contact' di private_messages_type_check & messages_type_check
--     (basis = daftar LIVE, jadi 15 tipe lama TIDAK hilang).
--  2) Kolom contact jsonb di kedua tabel. Dua bentuk payload:
--       kirim kontak ChatYuk : {"t":"user","u":"<uid>"}   (HANYA id; penerima
--                              resolve nama/foto sendiri → privasi terjaga)
--       kirim kontak HP      : {"t":"phone","n":"Nama","p":["+62…", …]}
--     Disimpan DI BARIS PESAN supaya bubble tampil lengkap dari cache lokal di
--     frame pertama (tanpa fetch).
--  3) text pesan = '📇 <nama>' → notif & last_message rapi lewat cabang teks
--     yang sudah ada (fungsi notif FROZEN tak disentuh).

alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker',
      'file','poll','contact'
    ])
  );

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker',
      'file','poll','contact'
    ])
  );

alter table public.private_messages add column if not exists contact jsonb;
alter table public.messages add column if not exists contact jsonb;
