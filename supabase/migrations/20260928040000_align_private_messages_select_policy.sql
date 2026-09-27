-- ============================================================
-- Selaraskan drift: policy SELECT private_messages (samakan dengan PROD)
--
-- Latar: `20260901010000_rpc_chat.sql` menetapkan policy
--   private_messages_select  =  using (false)
-- (niat awal: paksa client lewat RPC). Di PROD, policy ini DIKEMBALIKAN ke
-- versi "peserta chat bisa baca" (dikonfirmasi via Management API):
--   exists (select 1 from private_chats pc
--           where pc.chat_id = private_messages.chat_id
--             and private_messages.chat_id is not null
--             and pc.participants @> ARRAY[auth.uid()])
-- tapi perubahan itu TIDAK pernah ditulis sebagai file migration → fresh-replay
-- lokal menghasilkan policy=false.
--
-- Akibat di lokal: client & realtime TIDAK bisa membaca pesan private
-- (termasuk pesan type='gift' hasil send_gift) → "hadiah terkirim tapi tidak
-- muncul di chat".
--
-- Migration ini menyamakan lokal dengan prod. Idempotent.
-- ============================================================

drop policy if exists private_messages_select on public.private_messages;
create policy private_messages_select on public.private_messages
  for select using (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and private_messages.chat_id is not null
        and pc.participants @> array[auth.uid()]
    )
  );
