-- Lapis 3: Random Video Call — antrean match, penjaga riwayat & billing.
-- Jalankan: scripts/run_sql_tests.sh random_match_test.sql
-- Transaksional (begin/rollback) — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a1'::uuid, '[TEST] RndA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a2'::uuid, '[TEST] RndB', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a3'::uuid, '[TEST] RndC', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000a4'::uuid, '[TEST] RndD', 'online');

update public.profiles set gender = 'female', lat = -6.20, lon = 106.80
 where id = 'd0c1e000-0000-4000-8000-0000000000a2';
update public.profiles set lat = -6.21, lon = 106.81
 where id = 'd0c1e000-0000-4000-8000-0000000000a1';

create temp table _rm (k text primary key, v text) on commit drop;
grant all on _rm to service_role;

-- ── 0. Sebelum fitur dipublish: admin/anon ditolak, user biasa ditolak ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a1', true);
do $$
begin
  perform public.random_match_join('all');
  insert into _rm values ('flag_guard', 'lolos');
exception when others then
  insert into _rm values ('flag_guard', sqlerrm);
end $$;
select supabase_tests.check('fitur belum dipublish → FEATURE_DISABLED',
  (select v from _rm where k = 'flag_guard') = 'FEATURE_DISABLED',
  (select v from _rm where k = 'flag_guard'));

update public.app_settings
   set feature_flags = feature_flags || '{"random_call":{"published":true}}'::jsonb
 where id = 'global';

-- ── 1. A menunggu, B masuk → langsung matched (tanpa ringing) ──
insert into _rm values ('a_join', public.random_match_join('all')::text);
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a2', true);
insert into _rm values ('b_join', public.random_match_join('all')::text);

select supabase_tests.check('A (sendiri) → waiting',
  (select v::jsonb->>'status' from _rm where k = 'a_join') = 'waiting');
select supabase_tests.check('B masuk → matched',
  (select v::jsonb->>'status' from _rm where k = 'b_join') = 'matched');
select supabase_tests.check('call kind=random & status=answered (tanpa ringing)',
  exists(select 1 from public.calls
          where id = (select (v::jsonb->>'call_id')::uuid from _rm where k = 'b_join')
            and kind = 'random' and status = 'answered' and answered_at is not null));
select supabase_tests.check('peserta = A & B',
  exists(select 1 from public.calls
          where id = (select (v::jsonb->>'call_id')::uuid from _rm where k = 'b_join')
            and caller_id = 'd0c1e000-0000-4000-8000-0000000000a2'
            and callee_id = 'd0c1e000-0000-4000-8000-0000000000a1'));
select supabase_tests.check('kedua baris antrean menunjuk call yang sama',
  (select count(*) from public.random_match_queue
    where matched_call_id = (select (v::jsonb->>'call_id')::uuid from _rm where k = 'b_join')) = 2);

-- ── 2. Riwayat: call random TIDAK menulis bubble ke private chat ──
update public.calls
   set status = 'ended', ended_at = now() + interval '20 seconds'
 where id = (select (v::jsonb->>'call_id')::uuid from _rm where k = 'b_join');
select supabase_tests.check('call random selesai → TIDAK ada bubble "call" di chat',
  not exists(select 1 from public.private_messages
              where type = 'call'
                and (chat_id like '%d0c1e000-0000-4000-8000-0000000000a1%'
                     and chat_id like '%d0c1e000-0000-4000-8000-0000000000a2%')));

select supabase_tests.check('random_call_history memuat call tadi (durasi 20 dtk)',
  exists(select 1 from public.random_call_history(50, 0) h
          where h.call_id = (select (v::jsonb->>'call_id')::uuid from _rm where k = 'b_join')
            and h.duration_sec >= 20));

-- ── 3. Billing random = gratis ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a2', true);
insert into _rm values ('bill', public.call_billing_tick(
  (select (v::jsonb->>'call_id')::uuid from _rm where k = 'b_join'))::text);
select supabase_tests.check('billing random: per_minute 0 & tidak ditagih',
  (select (v::jsonb->>'per_minute')::int = 0
      and (v::jsonb->>'charged_total')::int = 0
      and (v::jsonb->>'can_continue')::boolean
     from _rm where k = 'bill'));

-- ── 4. Pasangan yang sama tidak dipasangkan lagi ≤10 menit ──
delete from public.random_match_queue;
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a1', true);
insert into _rm values ('a2', public.random_match_join('all')::text);
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a2', true);
insert into _rm values ('b2', public.random_match_join('all')::text);
select supabase_tests.check('pasangan sama ≤10 menit tidak diulang',
  (select v::jsonb->>'status' from _rm where k = 'b2') = 'waiting');

-- ── 5. Filter gender dua arah ──
delete from public.random_match_queue;
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a3', true);
insert into _rm values ('c_join', public.random_match_join('female')::text); -- C cowok ingin cewek
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a4', true);
insert into _rm values ('d_join', public.random_match_join('all')::text);    -- D cowok
select supabase_tests.check('gender tidak cocok → tidak match',
  (select v::jsonb->>'status' from _rm where k = 'd_join') = 'waiting');

-- ── 6. Saling blokir tidak dipasangkan ──
delete from public.random_match_queue;
insert into public.blocks (blocker_id, blocked_id)
values ('d0c1e000-0000-4000-8000-0000000000a3', 'd0c1e000-0000-4000-8000-0000000000a4');
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a3', true);
insert into _rm values ('c_blk', public.random_match_join('all')::text);
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a4', true);
insert into _rm values ('d_blk', public.random_match_join('all')::text);
select supabase_tests.check('saling blokir → tidak match',
  (select v::jsonb->>'status' from _rm where k = 'd_blk') = 'waiting');

-- ── 7. Antrean basi (>30 dtk) tidak dipasangkan ──
delete from public.random_match_queue;
delete from public.blocks;
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a3', true);
insert into _rm values ('c_stale', public.random_match_join('all')::text);
update public.random_match_queue set pinged_at = now() - interval '2 minutes'
 where user_id = 'd0c1e000-0000-4000-8000-0000000000a3';
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000a4', true);
insert into _rm values ('d_stale', public.random_match_join('all')::text);
select supabase_tests.check('penunggu basi tidak dipasangkan',
  (select v::jsonb->>'status' from _rm where k = 'd_stale') = 'waiting');

-- ── 8. Sweep membersihkan antrean basi ──
insert into _rm values ('sweep', public.random_match_sweep()::text);
select supabase_tests.check('sweep menghapus antrean basi',
  (select (v::jsonb->>'queue')::int >= 1 from _rm where k = 'sweep'));

-- ── 9. Leave ──
select public.random_match_leave();
select supabase_tests.check('leave menghapus baris antrean sendiri',
  not exists(select 1 from public.random_match_queue
              where user_id = 'd0c1e000-0000-4000-8000-0000000000a4'));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
