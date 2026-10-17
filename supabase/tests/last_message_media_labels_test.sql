-- Label media last_message private chat (20261018140000).
-- Jalankan: scripts/run_sql_tests.sh last_message_media_labels_test.sql
-- Transaksional (BEGIN/ROLLBACK) — HANYA akun dummy [TEST].
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b1'::uuid, 'TEST LabelA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b2'::uuid, 'TEST LabelB', 'online');
insert into public.private_chats (chat_id, participants) values
 ('test-label-ab', array['d0c1e000-0000-4000-8000-0000000000b1','d0c1e000-0000-4000-8000-0000000000b2']::uuid[]);

create or replace function pg_temp.send(p_type text, p_text text, p_img text, p_voice text)
returns text language plpgsql as $$
begin
  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender,
    text, type, image_data, image_path, voice_path)
  values ('test-label-ab', 'd0c1e000-0000-4000-8000-0000000000b1', 'TEST LabelA', 'male',
    p_text, p_type, p_img, '', p_voice);
  return (select last_message from public.private_chats where chat_id = 'test-label-ab');
end $$;

select supabase_tests.check('stiker → [Stiker]',
  pg_temp.send('sticker', '', 'stickers/d0c1e000-0000-4000-8000-0000000000b1/1.png', '') = '[Stiker]');
select supabase_tests.check('voice → [Pesan suara]',
  pg_temp.send('voice', '', '', 'voice/test-label-ab/1.m4a') = '[Pesan suara]');
select supabase_tests.check('video tanpa caption → [Video]',
  pg_temp.send('video', '', 'chat/test-label-ab/1.mp4', '') = '[Video]');
select supabase_tests.check('video BERcaption → caption',
  pg_temp.send('video', '[TEST] liburan', 'chat/test-label-ab/2.mp4', '') = '[TEST] liburan');
select supabase_tests.check('teks biasa tetap teks',
  pg_temp.send('text', '[TEST] halo', '', '') = '[TEST] halo');
select supabase_tests.check('foto tetap [Foto] (cabang lama utuh)',
  pg_temp.send('image', '', 'chat/test-label-ab/3.jpg', '') = '[Foto]');

-- Notif: cabang baru ada, cabang lama tetap ada.
select supabase_tests.check('notify: label stiker & lokasi + cabang lama utuh',
  (select prosrc like '%''[Stiker]''%' and prosrc like '%''[Lokasi]''%'
          and prosrc like '%''[Pesan suara]''%' and prosrc like '%Panggilan tak terjawab%'
   from pg_proc where proname = 'notify_private_message'));

select supabase_tests.report() as result;
rollback;
