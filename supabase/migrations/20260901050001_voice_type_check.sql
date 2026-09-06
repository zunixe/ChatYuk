-- Voice message: izinkan type='voice' di CHECK constraint
-- Sebelumnya insert type='voice' gagal diam-diam (violates check constraint)
alter table public.private_messages drop constraint if exists private_messages_type_check;
alter table public.private_messages add constraint private_messages_type_check
  check (type = any (array['text'::text,'image'::text,'view_once'::text,'view_once_expired'::text,'coin'::text,'gift'::text,'call'::text,'voice'::text]));

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type = any (array['text'::text,'image'::text,'view_once'::text,'view_once_expired'::text,'voice'::text]));
