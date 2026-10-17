-- Backfill label last_message yang terlanjur KOSONG (stiker/voice/video
-- tanpa caption) sebelum 20261018140000. Hanya kolom last_message — waktu,
-- unread & urutan chat TIDAK disentuh. Saat ditulis: 5 chat (3 voice, 2 stiker).
with last as (
  select distinct on (m.chat_id) m.chat_id, m.type, coalesce(m.text, '') as text
  from public.private_messages m
  where coalesce(m.is_deleted, false) = false
  order by m.chat_id, m.created_at desc
)
update public.private_chats pc
set last_message = case
  when l.type = 'sticker' then '[Stiker]'
  when l.type = 'voice' then '[Pesan suara]'
  else '[Video]' end
from last l
where l.chat_id = pc.chat_id
  and coalesce(pc.last_message, '') = ''
  and pc.message_count > 0
  and (l.type in ('sticker', 'voice')
       or (l.type in ('video', 'video_once', 'video_once_expired') and l.text = ''));
