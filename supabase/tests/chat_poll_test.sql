-- Poll private chat (20261018130000_chat_poll.sql).
-- Jalankan: scripts/run_sql_tests.sh chat_poll_test.sql
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

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a1'::uuid, 'TEST PollA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a2'::uuid, 'TEST PollB', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a3'::uuid, 'TEST Outsider', 'online');

insert into public.private_chats (chat_id, participants) values
 ('test-poll-ab', array['d0c1e000-0000-4000-8000-0000000000a1','d0c1e000-0000-4000-8000-0000000000a2']::uuid[]);

insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, poll)
values ('test-poll-ab', 'd0c1e000-0000-4000-8000-0000000000a1', 'TEST PollA', 'male',
        '📊 [TEST] Makan apa?', 'poll',
        '{"q":"[TEST] Makan apa?","o":["Bakso","Soto","Mie"],"m":false}'::jsonb);
create temp table t_poll as
  select id from public.private_messages where chat_id = 'test-poll-ab' and type = 'poll';

select supabase_tests.check('type poll diterima + kolom poll tersimpan',
  (select count(*) from t_poll) = 1);

-- Peserta B memilih opsi 1.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-0000000000a2","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('vote_poll: counts & mine benar',
  (select (r->'counts') = '[0,1,0]'::jsonb and (r->'mine') = '[1]'::jsonb
          and (r->>'voters')::int = 1
   from (select public.vote_poll((select id from t_poll), array[1]) as r) x));

-- Ganti pilihan → suara lama diganti (bukan bertambah).
select supabase_tests.check('vote ulang mengganti pilihan',
  (select (r->'counts') = '[0,0,1]'::jsonb
   from (select public.vote_poll((select id from t_poll), array[2]) as r) x));

select supabase_tests.check('poll pilih-satu menolak >1 opsi',
  pg_temp.raises(format('select public.vote_poll(%s, array[0,1])', (select id from t_poll))));
select supabase_tests.check('opsi di luar rentang ditolak',
  pg_temp.raises(format('select public.vote_poll(%s, array[5])', (select id from t_poll))));

-- Tarik suara (array kosong).
select supabase_tests.check('array kosong = tarik suara',
  (select (r->'counts') = '[0,0,0]'::jsonb and (r->>'voters')::int = 0
   from (select public.vote_poll((select id from t_poll), '{}'::int[]) as r) x));

-- Orang luar chat: tidak bisa vote & tidak dapat hasil.
select set_config('request.jwt.claims',
  '{"sub":"d0c1e000-0000-4000-8000-0000000000a3","email":"t@t.local","role":"authenticated"}', false);
select supabase_tests.check('non-peserta tidak bisa vote',
  pg_temp.raises(format('select public.vote_poll(%s, array[0])', (select id from t_poll))));
select supabase_tests.check('non-peserta tidak dapat hasil',
  public.get_poll_results(array[(select id from t_poll)]) = '[]'::jsonb);

-- Tabel suara tak bisa ditulis langsung oleh authenticated.
select supabase_tests.check('authenticated tak punya INSERT langsung',
  not has_table_privilege('authenticated', 'public.chat_poll_votes', 'INSERT'));

select supabase_tests.report() as result;
rollback;
