-- Lapis 3: update_room_icon (owner/admin boleh, member/lain tidak) — 20261009180000.
-- Jalankan: scripts/run_sql_tests.sh update_room_icon_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
--
-- CATATAN: RPC dipanggil di STATEMENT TERPISAH (via DO block yg menyimpan hasil
-- ke tabel uji), bukan di dalam argumen supabase_tests.check() — check()
-- security-definer mengubah konteks sehingga auth.uid() di dalam RPC terbaca
-- null saat dipanggil sebagai argumen.
begin;
select supabase_tests.begin_tests();

create temp table rres(name text primary key, resp jsonb);

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000071'::uuid, 'TEST Owner', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-000000000072'::uuid, 'TEST Member', 'online');

insert into public.rooms (id, name, icon, category, is_private, owner_id)
values ('test-room-icon-1', 'Test Room', '💬', 'general', true,
        'd0c1e000-0000-4000-8000-000000000071'::uuid);
insert into public.room_members (room_id, user_id, role)
values ('test-room-icon-1', 'd0c1e000-0000-4000-8000-000000000072'::uuid, 'member');

-- (a) owner boleh ganti icon.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000071","role":"authenticated"}', false);
do $$
begin
  insert into rres(name, resp) values ('a', public.update_room_icon('test-room-icon-1', 'room-icons/o/x.jpg'));
end $$;
select supabase_tests.check('owner boleh ganti icon',
  (select resp->>'ok' from rres where name='a') = 'true'
  and (select icon from public.rooms where id='test-room-icon-1') = 'room-icons/o/x.jpg');

-- (b) member TIDAK boleh.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000072","role":"authenticated"}', false);
do $$
begin
  insert into rres(name, resp) values ('b', public.update_room_icon('test-room-icon-1', '💥'));
end $$;
select supabase_tests.check('member ditolak (forbidden)',
  (select resp->>'reason' from rres where name='b') = 'forbidden'
  and (select icon from public.rooms where id='test-room-icon-1') = 'room-icons/o/x.jpg');

-- (c) icon kosong ditolak.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-000000000071","role":"authenticated"}', false);
do $$
begin
  insert into rres(name, resp) values ('c', public.update_room_icon('test-room-icon-1', '   '));
end $$;
select supabase_tests.check('icon kosong ditolak',
  (select resp->>'reason' from rres where name='c') = 'bad_icon');

select supabase_tests.report() as result;
rollback;
