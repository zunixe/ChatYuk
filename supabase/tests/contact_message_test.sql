-- KIRIM KONTAK (20261018170000_contact_message.sql): type 'contact' + kolom contact.
-- Jalankan: scripts/run_sql_tests.sh contact_message_test.sql
-- Transaksional (BEGIN/ROLLBACK) — HANYA akun dummy [TEST], data produksi aman.
begin;
select supabase_tests.begin_tests();

create or replace function pg_temp.raises(q text) returns boolean
language plpgsql as $$
begin
  execute q;
  return false;
exception when others then
  return true;
end $$;

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000c1'::uuid, 'TEST ContactA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000c2'::uuid, 'TEST ContactB', 'online');

-- ── PRIVATE ──
insert into public.private_chats (chat_id, participants) values
 ('test-contact-ab',
  array['d0c1e000-0000-4000-8000-0000000000c1',
        'd0c1e000-0000-4000-8000-0000000000c2']::uuid[]);

-- (a) kirim kontak ChatYuk: payload HANYA id.
insert into public.private_messages
  (chat_id, sender_id, sender_name, sender_gender, text, type, contact)
values
 ('test-contact-ab', 'd0c1e000-0000-4000-8000-0000000000c1', 'TEST ContactA', 'male',
  '📇 [TEST] ContactB', 'contact',
  '{"t":"user","u":"d0c1e000-0000-4000-8000-0000000000c2"}'::jsonb);

select supabase_tests.check('private: type contact diterima + payload user (uid saja) tersimpan',
  (select count(*) from public.private_messages
   where chat_id = 'test-contact-ab' and type = 'contact'
     and contact->>'t' = 'user'
     and contact->>'u' = 'd0c1e000-0000-4000-8000-0000000000c2'
     and contact ? 'n' = false) = 1);

-- (b) kirim kontak HP: nama + daftar nomor.
insert into public.private_messages
  (chat_id, sender_id, sender_name, sender_gender, text, type, contact)
values
 ('test-contact-ab', 'd0c1e000-0000-4000-8000-0000000000c1', 'TEST ContactA', 'male',
  '📇 [TEST] Budi HP', 'contact',
  '{"t":"phone","n":"[TEST] Budi HP","p":["+6281200000001","+6281200000002"]}'::jsonb);

select supabase_tests.check('private: payload phone (nama + 2 nomor) tersimpan',
  (select count(*) from public.private_messages
   where chat_id = 'test-contact-ab' and type = 'contact'
     and contact->>'t' = 'phone'
     and contact->>'n' = '[TEST] Budi HP'
     and jsonb_array_length(contact->'p') = 2) = 1);

select supabase_tests.check('tipe tak dikenal tetap DITOLAK constraint',
  pg_temp.raises($q$
    insert into public.private_messages
      (chat_id, sender_id, sender_name, sender_gender, text, type)
    values ('test-contact-ab', 'd0c1e000-0000-4000-8000-0000000000c1',
            'TEST ContactA', 'male', 'x', 'contact_x')
  $q$));

-- ── ROOM / GRUP ──
insert into public.rooms (id, name, is_private, owner_id) values
 ('test-room-contact', '[TEST] Contact Room', false,
  'd0c1e000-0000-4000-8000-0000000000c1'::uuid);

insert into public.messages
  (room_id, sender_id, sender_name, sender_gender, text, type, contact)
values
 ('test-room-contact', 'd0c1e000-0000-4000-8000-0000000000c1', 'TEST ContactA', 'male',
  '📇 [TEST] Budi HP', 'contact',
  '{"t":"phone","n":"[TEST] Budi HP","p":["+6281200000001"]}'::jsonb);

select supabase_tests.check('room: type contact diterima + payload tersimpan',
  (select count(*) from public.messages
   where room_id = 'test-room-contact' and type = 'contact'
     and contact->>'n' = '[TEST] Budi HP') = 1);

select supabase_tests.report() as result;
rollback;
