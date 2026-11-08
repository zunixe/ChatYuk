-- Room v2 — sesi terjadwal + host (20261111120000_room_sessions_v2.sql).
-- Jalankan: scripts/run_sql_tests.sh room_sessions_test.sql
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

-- Akun uji: H host, V viewer (pengirim gift), N non-host, F female.
select supabase_tests.mk_dummy('e0a10000-0000-4000-8000-0000000000a1'::uuid, 'TEST RS-Host', 'online');
select supabase_tests.mk_dummy('e0a10000-0000-4000-8000-0000000000a2'::uuid, 'TEST RS-Viewer', 'online');
select supabase_tests.mk_dummy('e0a10000-0000-4000-8000-0000000000a3'::uuid, 'TEST RS-NonHost', 'online');
select supabase_tests.mk_dummy('e0a10000-0000-4000-8000-0000000000a4'::uuid, 'TEST RS-Female', 'online');

update public.profiles set gender = 'male', is_registered = true,
       is_host = true, created_at = now() - interval '30 days'
 where id = 'e0a10000-0000-4000-8000-0000000000a1';
update public.profiles set gender = 'male', is_registered = true,
       created_at = now() - interval '30 days'
 where id in ('e0a10000-0000-4000-8000-0000000000a2',
              'e0a10000-0000-4000-8000-0000000000a3');
update public.profiles set gender = 'female', is_registered = true,
       created_at = now() - interval '30 days'
 where id = 'e0a10000-0000-4000-8000-0000000000a4';

update public.app_settings set points_enabled = true, gift_cut_pct = 30
 where id = 'global';

-- Room global uji + gift uji.
insert into public.rooms (id, name, is_private, country, category)
values ('test-room-rs', '[TEST] Room Sesi', false, 'Indonesia', 'general');
insert into public.gift_catalog (id, emoji, name_id, name_en, coins, active)
values ('test-gift-rs', '🎁', '[TEST] Gift', '[TEST] Gift', 100, true)
on conflict (id) do update set coins = 100, active = true;

-- Koin beli/penghasilan viewer (paid-only) + bonus (tidak boleh dipakai).
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
  ('e0a10000-0000-4000-8000-0000000000a2', 'topup', 'topup', 1000, '[TEST]rs');

create temp table _rs (k text primary key, v text) on commit drop;
grant all on _rs to service_role;

-- ════ S1. Admin jadwalkan sesi ════
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a1","email":"zunixe@gmail.com","role":"authenticated"}', false);

create temp table _rs_res (k text primary key, v jsonb) on commit drop;
grant all on _rs_res to service_role;
insert into _rs_res values ('s1', public.schedule_room_session(
  'test-room-rs', 'e0a10000-0000-4000-8000-0000000000a1',
  '[TEST] Karaoke Malam', 'karaoke',
  now() + interval '10 minutes', now() + interval '70 minutes'));
select supabase_tests.check('S1: admin schedule → ok, status scheduled',
  (select (v->>'ok')::boolean from _rs_res where k='s1') and exists (
     select 1 from public.room_sessions
      where id = ((select v->>'session_id' from _rs_res where k='s1'))::bigint
        and status = 'scheduled'));

-- Non-admin tidak boleh jadwalkan.
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a3","email":"n@test.local","role":"authenticated"}', false);
select supabase_tests.check('S2: non-admin schedule → ditolak',
  pg_temp.raises($q$select public.schedule_room_session(
    'test-room-rs', 'e0a10000-0000-4000-8000-0000000000a1',
    '[TEST] X', 'bebas', now() + interval '2 hours', now() + interval '3 hours')$q$));

-- Host non-host flag → ditolak.
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a1","email":"zunixe@gmail.com","role":"authenticated"}', false);
select supabase_tests.check('S3: host is_host=false → ditolak',
  pg_temp.raises($q$select public.schedule_room_session(
    'test-room-rs', 'e0a10000-0000-4000-8000-0000000000a3',
    '[TEST] X', 'bebas', now() + interval '2 hours', now() + interval '3 hours')$q$));

-- Overlap rentang → ditolak.
select supabase_tests.check('S4: sesi overlap di room sama → ditolak',
  pg_temp.raises($q$select public.schedule_room_session(
    'test-room-rs', 'e0a10000-0000-4000-8000-0000000000a1',
    '[TEST] X', 'bebas', now() + interval '30 minutes', now() + interval '40 minutes')$q$));

-- Jam terbalik → ditolak.
select supabase_tests.check('S5: starts_at >= ends_at → ditolak',
  pg_temp.raises($q$select public.schedule_room_session(
    'test-room-rs', 'e0a10000-0000-4000-8000-0000000000a1',
    '[TEST] X', 'bebas', now() + interval '3 hours', now() + interval '2 hours')$q$));

-- Format invalid → ditolak.
select supabase_tests.check('S6: format invalid → ditolak',
  pg_temp.raises($q$select public.schedule_room_session(
    'test-room-rs', 'e0a10000-0000-4000-8000-0000000000a1',
    '[TEST] X', 'ngawur', now() + interval '2 hours', now() + interval '3 hours')$q$));

-- ════ S7. Reminder toggle ════
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a2","email":"v@test.local","role":"authenticated"}', false);
select supabase_tests.check('S7a: toggle reminder → reminded=true',
  (select (r->>'reminded')::boolean
   from (select public.toggle_session_reminder(
     (select id from public.room_sessions where room_id='test-room-rs' and status='scheduled' limit 1)) as r) x));
select supabase_tests.check('S7b: toggle lagi → reminded=false',
  (select not (r->>'reminded')::boolean
   from (select public.toggle_session_reminder(
     (select id from public.room_sessions where room_id='test-room-rs' and status='scheduled' limit 1)) as r) x));
-- Pasang lagi untuk uji next_room_sessions + notif.
select public.toggle_session_reminder(
  (select id from public.room_sessions where room_id='test-room-rs' and status='scheduled' limit 1));

-- ════ S8. next_room_sessions ════
select supabase_tests.check('S8: next_room_sessions → 1 baris, scheduled, reminded',
  (select count(*) = 1 and bool_and(status = 'scheduled')
          and bool_and(host_name = 'TEST RS-Host') and bool_and(reminded)
   from public.next_room_sessions(array['test-room-rs'])));

-- ════ S9. Start sesi ════
-- Bukan host → ditolak.
select supabase_tests.check('S9a: non-host start → ditolak',
  pg_temp.raises(format('select public.start_room_session(%s)',
    (select id from public.room_sessions where room_id='test-room-rs' and status='scheduled' limit 1))));

select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a1","email":"h@test.local","role":"authenticated"}', false);
insert into _rs_res values ('s9', public.start_room_session(
  (select id from public.room_sessions where room_id='test-room-rs' and status='scheduled' limit 1)));
select supabase_tests.check('S9b: host start → live + started_at terisi',
  (select (v->>'ok')::boolean from _rs_res where k='s9') and exists (
     select 1 from public.room_sessions
      where id = ((select v->>'session_id' from _rs_res where k='s9'))::bigint
        and status = 'live' and started_at is not null));

-- ════ S10. Gift: tanpa sesi live ditolak (room global lain) ════
insert into public.rooms (id, name, is_private, country, category)
values ('test-room-rs2', '[TEST] Room Kosong', false, 'Indonesia', 'general');
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a2","email":"v@test.local","role":"authenticated"}', false);
select supabase_tests.check('S10: gift room global tanpa sesi live → ditolak',
  pg_temp.raises($q$select public.send_room_gift('test-room-rs2','test-gift-rs',1)$q$));

-- ════ S11. Gift saat live → ke host ════
insert into _rs_res values ('s11', public.send_room_gift('test-room-rs','test-gift-rs',1));
select supabase_tests.check('S11a: gift live → host earned += 70, sesi gifts_total += 100',
  (select (v->>'ok')::boolean and (v->>'net')::int = 70 from _rs_res where k='s11')
  and exists (select 1 from public.coin_ledger
               where user_id='e0a10000-0000-4000-8000-0000000000a1'
                 and bucket='earned' and type='gift_recv' and amount=70)
  and exists (select 1 from public.room_sessions
               where room_id='test-room-rs' and status='live' and gifts_total = 100));
select supabase_tests.check('S11b: ledger debit + platform cut + bubble gift',
  exists (select 1 from public.coin_ledger
           where user_id='e0a10000-0000-4000-8000-0000000000a2'
             and type='gift_sent' and amount = -100)
  and exists (select 1 from public.platform_revenue
               where ref_id='test-room-rs' and source='gift_cut' and amount=30)
  and exists (select 1 from public.messages
               where room_id='test-room-rs' and type='gift'
                 and sender_id='e0a10000-0000-4000-8000-0000000000a2'));

-- ════ S12. Female tidak bisa kirim gift ════
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a4","email":"f@test.local","role":"authenticated"}', false);
select supabase_tests.check('S12: female send_room_gift → ditolak',
  pg_temp.raises($q$select public.send_room_gift('test-room-rs','test-gift-rs',1)$q$));

-- ════ S13. Bonus-only tidak bisa gift ════
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id) values
  ('e0a10000-0000-4000-8000-0000000000a3', 'bonus', 'mission_reward', 5000, '[TEST]rs');
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a3","email":"n@test.local","role":"authenticated"}', false);
select supabase_tests.check('S13: bonus-only gift → ditolak (paid-only)',
  pg_temp.raises($q$select public.send_room_gift('test-room-rs','test-gift-rs',1)$q$));

-- ════ S14. peak_viewers tanpa dummy ════
-- Semua akun uji terdaftar di dummy_accounts → presence mereka TIDAK dihitung.
insert into public.room_presence (room_id, user_id, nickname)
values ('test-room-rs', 'e0a10000-0000-4000-8000-0000000000a2', 'TEST RS-Viewer')
on conflict do nothing;
select supabase_tests.check('S14a: tick → viewers 0 (dummy dikecualikan)',
  (select (r->>'viewers')::int = 0 and (r->>'live')::boolean
   from (select public.room_session_tick('test-room-rs') as r) x));

-- Satu user non-dummy (bukan akun asli — uuid sintetis, rollback) → dihitung.
insert into auth.users (id, instance_id, aud, role, email,
  encrypted_password, email_confirmed_at, created_at, updated_at)
values ('e0a10000-0000-4000-8000-0000000000ff',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'rs-real@test.local', '', now(), now(), now())
on conflict (id) do nothing;
insert into public.profiles (id, nickname, gender, age)
values ('e0a10000-0000-4000-8000-0000000000ff', 'TEST RS-Real', 'male', 25)
on conflict (id) do nothing;
insert into public.room_presence (room_id, user_id, nickname)
values ('test-room-rs', 'e0a10000-0000-4000-8000-0000000000ff', 'TEST RS-Real')
on conflict do nothing;
select supabase_tests.check('S14b: tick → viewers 1, peak tersimpan',
  (select (r->>'viewers')::int = 1 and (r->>'peak')::int >= 1
   from (select public.room_session_tick('test-room-rs') as r) x));

-- ════ S15. session_host_mute ════
insert into public.room_voice_speakers (room_id, uid) values
  ('test-room-rs', 'e0a10000-0000-4000-8000-0000000000a2')
on conflict do nothing;
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a3","email":"n@test.local","role":"authenticated"}', false);
select supabase_tests.check('S15a: non-host mute → ditolak',
  pg_temp.raises($q$select public.session_host_mute('test-room-rs','e0a10000-0000-4000-8000-0000000000a2')$q$));
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a1","email":"h@test.local","role":"authenticated"}', false);
insert into _rs_res values ('s15', public.session_host_mute('test-room-rs','e0a10000-0000-4000-8000-0000000000a2'));
select supabase_tests.check('S15b: host sesi mute → ok + speaker turun + sinyal v_mute',
  (select (v->>'ok')::boolean from _rs_res where k='s15')
  and not exists (select 1 from public.room_voice_speakers
                   where room_id='test-room-rs' and uid='e0a10000-0000-4000-8000-0000000000a2')
  and exists (select 1 from public.room_voice_signals
               where room_id='test-room-rs' and to_uid='e0a10000-0000-4000-8000-0000000000a2'
                 and type='v_mute'));

-- ════ S16. End sesi ════
insert into _rs_res values ('s16', public.end_room_session(
  (select id from public.room_sessions where room_id='test-room-rs' and status='live' limit 1)));
select supabase_tests.check('S16: host end → ended + ended_at terisi',
  (select (v->>'ok')::boolean from _rs_res where k='s16') and exists (
     select 1 from public.room_sessions
      where room_id='test-room-rs' and status='ended' and ended_at is not null));

-- ════ S17. Sweep auto-end ════
insert into public.room_sessions
  (room_id, host_uid, title, format, starts_at, ends_at, status, started_at, created_by)
values
  ('test-room-rs2', 'e0a10000-0000-4000-8000-0000000000a1', '[TEST] Basi', 'bebas',
   now() - interval '5 hours', now() - interval '3 hours', 'live',
   now() - interval '5 hours', 'e0a10000-0000-4000-8000-0000000000a1');
create temp table _rs_sweep as select public.room_session_sweep() as n;
select supabase_tests.check('S17: sweep → sesi live basi > ends_at+2j di-end',
  (select n >= 1 from _rs_sweep)
  and exists (select 1 from public.room_sessions
               where room_id='test-room-rs2' and status='ended'));

-- ════ S18. Admin KPI ════
select set_config('request.jwt.claims',
  '{"sub":"e0a10000-0000-4000-8000-0000000000a1","email":"zunixe@gmail.com","role":"authenticated"}', false);
select supabase_tests.check('S18: admin_room_session_stats → KPI terisi',
  (select (r->>'sessions')::int >= 2
          and (r->>'total_gifts')::int >= 100
          and (r->>'on_time_pct') is not null
   from (select public.admin_room_session_stats(30) as r) x));

select supabase_tests.report();
rollback;
