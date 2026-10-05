-- ============================================================
-- Kartu list private chat: preview ikut teks HASIL EDIT.
--
-- MASALAH (laporan user): pesan terakhir diedit → kartu list masih
-- menampilkan teks LAMA. Penyebab: `editPrivateMessage` hanya UPDATE
-- `private_messages.text`, sedangkan preview kartu dibaca dari kolom
-- denormalisasi `private_chats.last_message` yang hanya ditulis trigger
-- `trg_private_msg` (AFTER INSERT). Edit = UPDATE → preview basi.
--
-- FIX: trigger AFTER UPDATE OF text — bila teks berubah DAN pesan yang
-- diedit masih yang TERAKHIR di chat, tulis ulang `last_message` dengan
-- format yang SAMA persis seperti `handle_new_private_message`
-- ([Foto]/[Koin]/[Hadiah]/teks). Bila sudah ada pesan lebih baru,
-- preview milik pesan itu → jangan timpa. Tidak menyentuh unread/
-- count/at (edit bukan pesan baru).
--
-- Idempotent. Tidak FROZEN (fungsi BARU, tidak redefine yang ada).
-- ============================================================

create or replace function public.sync_private_last_message_on_edit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.text is not distinct from old.text then
    return new;
  end if;
  update public.private_chats pc
     set last_message = case
       when new.type = 'image' then '[Foto]'
       when new.type = 'view_once' then '[Foto]'
       when new.type = 'coin' then '[Koin]'
       when new.type = 'gift' then '[Hadiah]'
       else new.text end
   where pc.chat_id = new.chat_id
     and not exists (
       select 1 from public.private_messages m
        where m.chat_id = new.chat_id
          and (m.created_at, m.id) > (new.created_at, new.id)
     );
  return new;
end;
$$;

drop trigger if exists trg_private_msg_edit on public.private_messages;
create trigger trg_private_msg_edit
  after update of text on public.private_messages
  for each row execute function public.sync_private_last_message_on_edit();

-- Verifikasi setelah apply:
--   select tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid
--    where c.relname='private_messages' and tgname='trg_private_msg_edit';
