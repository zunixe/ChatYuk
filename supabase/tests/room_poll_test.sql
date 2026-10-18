-- Poll GRUP/GLOBAL ROOM (20261018150000_room_poll.sql).
-- Jalankan: scripts/run_sql_tests.sh room_poll_test.sql
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

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b1'::uuid, 'TEST RoomPollA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b2'::uuid, 'TEST RoomPollB', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b3'::uuid, 'TEST RoomPollOut', 'online');

-- Room PRIVAT (grup) + anggota: b1 owner, b2 member; b3 bukan anggota.
insert into public.rooms (id, name, is_private, owner_id) values
 ('test-room-poll', '[TEST] Poll Room', true,
  'd0c1e000-0000-4000-8000-0000000000b1'::uuid);
insert into public.room_members (room_id, user_id, role) values
 ('test-room-poll', 'd0c1e000-0000-4000-8000-0000000000b1'::uuid, 'owner'),
 ('test-room-poll', 'd0c1e000-0000-4000-8000-0000000000b2'::uuid, 'member');

insert into public.messages
  (room_id, sender_id, sender_name, sender_gender, text, type, poll)
values
 ('test-room-poll', 'd0c1e000-0000-4000-8000-0000000000b1', 'TEST RoomPollA', 'male',
  '📊 [TEST] Makan apa?', 'poll',
  '{"q":"[TEST] Makan apa?","o":["Bakso","Soto","Mie"],"m":false}'::jsonb);
create temp table t_rpoll as
  select id from public.messages
  where room_id = 'test-room-poll' and type = 'poll';

select supabase_tests.check('type poll diterima di messages + kolom poll tersimpan',
  (select count(*) from t_rpoll) = 1);

-- Anggota B memilih opsi 1.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-0000000000b2","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('vote_room_poll: counts & mine benar',
  (select (r->'counts') = '[0,1,0]'::jsonb and (r->'mine') = '[1]'::jsonb
          and (r->>'voters')::int = 1
   from (select public.vote_room_poll((select id from t_rpoll), array[1]) as r) x));

select supabase_tests.check('vote ulang mengganti pilihan',
  (select (r->'counts') = '[0,0,1]'::jsonb
   from (select public.vote_room_poll((select id from t_rpoll), array[2]) as r) x));

select supabase_tests.check('poll pilih-satu menolak >1 opsi',
  pg_temp.raises(format('select public.vote_room_poll(%s, array[0,1])', (select id from t_rpoll))));
select supabase_tests.check('opsi di luar rentang ditolak',
  pg_temp.raises(format('select public.vote_room_poll(%s, array[5])', (select id from t_rpoll))));

select supabase_tests.check('array kosong = tarik suara',
  (select (r->'counts') = '[0,0,0]'::jsonb and (r->>'voters')::int = 0
   from (select public.vote_room_poll((select id from t_rpoll), '{}'::int[]) as r) x));

-- Bukan anggota room privat: tidak bisa vote & tidak dapat hasil.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-0000000000b3","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('non-anggota tidak bisa vote poll room privat',
  pg_temp.raises(format('select public.vote_room_poll(%s, array[0])', (select id from t_rpoll))));
select supabase_tests.check('non-anggota tidak dapat hasil (room privat)',
  public.get_room_poll_results(array[(select id from t_rpoll)]) = '[]'::jsonb);

-- Tabel suara tak bisa ditulis langsung oleh authenticated.
select supabase_tests.check('authenticated tak punya INSERT langsung (room)',
  not has_table_privilege('authenticated', 'public.room_poll_votes', 'INSERT'));

select supabase_tests.report() as result;
rollback;
