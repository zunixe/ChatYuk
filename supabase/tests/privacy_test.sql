-- Lapis 3: invariant PRIVASI (5 opsi visibility + pengecualian teman/anon).
-- Jalankan: scripts/run_sql_tests.sh privacy_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

-- Owner = A, teman = B (mutual follow), non-teman = C.
select supabase_tests.mk_dummy('aa000000-0000-0000-0000-00000000000a'::uuid, 'TEST Own');
select supabase_tests.mk_dummy('bb000000-0000-0000-0000-00000000000b'::uuid, 'TEST Friend');
select supabase_tests.mk_dummy('cc000000-0000-0000-0000-00000000000c'::uuid, 'TEST Stranger');

-- B jadi teman A (mutual follow).
insert into public.follows (follower_id, followee_id)
values ('aa000000-0000-0000-0000-00000000000a', 'bb000000-0000-0000-0000-00000000000b'),
       ('bb000000-0000-0000-0000-00000000000b', 'aa000000-0000-0000-0000-00000000000a')
on conflict do nothing;

-- Non-teman (C) tidak saling follow.

-- ── Helper teman (mutual follow, bukan friend_requests) ──
select supabase_tests.check('_privacy_are_friends: mutual follow = true',
  public._privacy_are_friends(
    'aa000000-0000-0000-0000-00000000000a',
    'bb000000-0000-0000-0000-00000000000b'));
select supabase_tests.check('_privacy_are_friends: satu arah = false',
  not public._privacy_are_friends(
    'aa000000-0000-0000-0000-00000000000a',
    'cc000000-0000-0000-0000-00000000000c'));

-- ── everyone: teman & non-teman sama-sama boleh ──
update public.profiles set about_visibility = 'everyone'
 where id = 'aa000000-0000-0000-0000-00000000000a';
select supabase_tests.check('everyone → teman boleh',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'bb000000-0000-0000-0000-00000000000b'));
select supabase_tests.check('everyone → non-teman boleh',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- ── nobody: semua ditolak (selain diri sendiri) ──
update public.profiles set about_visibility = 'nobody'
 where id = 'aa000000-0000-0000-0000-00000000000a';
select supabase_tests.check('nobody → teman ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'bb000000-0000-0000-0000-00000000000b'));
select supabase_tests.check('nobody → non-teman ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));
select supabase_tests.check('owner selalu boleh lihat diri sendiri',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'aa000000-0000-0000-0000-00000000000a'));

-- ── friends: hanya teman ──
update public.profiles set about_visibility = 'friends'
 where id = 'aa000000-0000-0000-0000-00000000000a';
select supabase_tests.check('friends → teman boleh',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'bb000000-0000-0000-0000-00000000000b'));
select supabase_tests.check('friends → non-teman ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- ── everyone_except: semua boleh, kecuali yang masuk daftar (anon) ──
update public.profiles set about_visibility = 'everyone_except'
 where id = 'aa000000-0000-0000-0000-00000000000a';
insert into public.profile_privacy_exclusions (owner_id, excluded_uid, field)
values ('aa000000-0000-0000-0000-00000000000a',
        'cc000000-0000-0000-0000-00000000000c', 'about')
on conflict do nothing;
select supabase_tests.check('everyone_except → teman boleh',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'bb000000-0000-0000-0000-00000000000b'));
select supabase_tests.check('everyone_except → yang dikecualikan ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- ── friends_except: teman boleh, teman yang dikecualikan ditolak ──
delete from public.profile_privacy_exclusions
 where owner_id = 'aa000000-0000-0000-0000-00000000000a';
update public.profiles set about_visibility = 'friends_except'
 where id = 'aa000000-0000-0000-0000-00000000000a';
select supabase_tests.check('friends_except → teman (bukan daftar) boleh',
  public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'bb000000-0000-0000-0000-00000000000b'));
insert into public.profile_privacy_exclusions (owner_id, excluded_uid, field)
values ('aa000000-0000-0000-0000-00000000000a',
        'bb000000-0000-0000-0000-00000000000b', 'about')
on conflict do nothing;
select supabase_tests.check('friends_except → teman dikecualikan ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'bb000000-0000-0000-0000-00000000000b'));
select supabase_tests.check('friends_except → non-teman tetap ditolak',
  not public.privacy_can_view('aa000000-0000-0000-0000-00000000000a','about',
    'cc000000-0000-0000-0000-00000000000c'));

-- ── Constraint memuat 5 opsi ──
select supabase_tests.check('constraint memuat everyone_except + friends_except',
  pg_get_constraintdef(
    (select oid from pg_constraint
      where conname = 'profiles_privacy_visibility_check')
  ) like '%everyone_except%'
  and pg_get_constraintdef(
    (select oid from pg_constraint
      where conname = 'profiles_privacy_visibility_check')
  ) like '%friends_except%');

-- ── RPC pendukung ada ──
select supabase_tests.check('RPC privacy_excludable_users ada',
  exists(select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'privacy_excludable_users'));
select supabase_tests.check('privacy_can_view memuat 5 opsi',
  (select pg_get_functiondef(p.oid) like '%everyone_except%'
     and pg_get_functiondef(p.oid) like '%friends_except%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'privacy_can_view' limit 1));

select supabase_tests.report() as result;
rollback;
