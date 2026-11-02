-- Lapis 3: Daily login streak v2 (halaman Bonus male).
-- Jalankan: scripts/run_sql_tests.sh daily_login_test.sql
-- Transaksional (begin/rollback) — hanya akun dummy test.
begin;
select supabase_tests.begin_tests();

select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b1'::uuid, '[TEST] BonusA', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000b2'::uuid, '[TEST] BonusB', 'online');

-- A = male, B = female.
update public.profiles set gender = 'male'
 where id = 'd0c1e000-0000-4000-8000-0000000000b1';
update public.profiles set gender = 'female'
 where id = 'd0c1e000-0000-4000-8000-0000000000b2';

create temp table _dl (k text primary key, v text) on commit drop;
grant all on _dl to service_role;

-- ── 1. Male pertama kali: streak 1 → +25 bucket bonus ──
update public.profiles set last_login_date = null, login_streak = 0
 where id = 'd0c1e000-0000-4000-8000-0000000000b1';
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000b1', true);
insert into _dl values ('claim1', public.daily_login_bonus()::text);
select supabase_tests.check('male klaim pertama → streak 1, bonus 25',
  (select v::jsonb->>'streak' from _dl where k = 'claim1') = '1'
  and (select v::jsonb->>'bonus' from _dl where k = 'claim1') = '25');
select supabase_tests.check('ledger: daily_login +25 bucket bonus',
  exists(select 1 from public.coin_ledger
          where user_id = 'd0c1e000-0000-4000-8000-0000000000b1'
            and type = 'daily_login' and amount = 25 and bucket = 'bonus'));
select supabase_tests.check('wallet sinkron = total ledger',
  (select v::jsonb->>'total' from _dl where k = 'claim1')::int
  = (select coalesce(sum(amount),0) from public.coin_ledger
      where user_id = 'd0c1e000-0000-4000-8000-0000000000b1'));

-- ── 2. Klaim ulang hari sama → idempotent (bonus 0) ──
insert into _dl values ('claim2', public.daily_login_bonus()::text);
select supabase_tests.check('klaim ulang hari sama → bonus 0, streak tetap',
  (select v::jsonb->>'bonus' from _dl where k = 'claim2') = '0'
  and (select v::jsonb->>'streak' from _dl where k = 'claim2') = '1');
select supabase_tests.check('tidak ada baris ledger baru',
  (select count(*) from public.coin_ledger
    where user_id = 'd0c1e000-0000-4000-8000-0000000000b1'
      and type = 'daily_login') = 1);

-- ── 3. Kemarin klaim → streak 2 → +30 ──
-- "Kemarin" harus memakai zona waktu USER (Asia/Jakarta), sama seperti
-- daily_login_bonus. Server ber-zona UTC, jadi `current_date - 1` bisa
-- berbeda dari "kemarin" yang dihitung fungsi → streak tidak naik.
update public.profiles
   set last_login_date = (now() AT TIME ZONE 'Asia/Jakarta')::date - 1,
       login_streak = 1
 where id = 'd0c1e000-0000-4000-8000-0000000000b1';
insert into _dl values ('claim3', public.daily_login_bonus()::text);
select supabase_tests.check('streak lanjut → streak 2, bonus 30',
  (select v::jsonb->>'streak' from _dl where k = 'claim3') = '2'
  and (select v::jsonb->>'bonus' from _dl where k = 'claim3') = '30');

-- ── 4. Streak 7 → siklus ulang ke hari 1 (+25) ──
-- Zona waktu USER (Asia/Jakarta), sama seperti daily_login_bonus.
update public.profiles
   set last_login_date = (now() AT TIME ZONE 'Asia/Jakarta')::date - 1,
       login_streak = 7
 where id = 'd0c1e000-0000-4000-8000-0000000000b1';
insert into _dl values ('claim4', public.daily_login_bonus()::text);
select supabase_tests.check('streak 7 → siklus ke 1, bonus 25',
  (select v::jsonb->>'streak' from _dl where k = 'claim4') = '1'
  and (select v::jsonb->>'bonus' from _dl where k = 'claim4') = '25');

-- ── 5. Streak putus (2 hari lalu) → reset ke 1 ──
-- Zona waktu USER (Asia/Jakarta), sama seperti daily_login_bonus.
update public.profiles
   set last_login_date = (now() AT TIME ZONE 'Asia/Jakarta')::date - 2,
       login_streak = 5
 where id = 'd0c1e000-0000-4000-8000-0000000000b1';
insert into _dl values ('claim5', public.daily_login_bonus()::text);
select supabase_tests.check('streak putus → reset ke 1, bonus 25',
  (select v::jsonb->>'streak' from _dl where k = 'claim5') = '1'
  and (select v::jsonb->>'bonus' from _dl where k = 'claim5') = '25');

-- ── 6. Female → tanpa kredit (idempotent state) ──
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000b2', true);
update public.profiles set last_login_date = null, login_streak = 0
 where id = 'd0c1e000-0000-4000-8000-0000000000b2';
insert into _dl values ('f_claim', public.daily_login_bonus()::text);
select supabase_tests.check('female → bonus 0 (tanpa kredit)',
  (select v::jsonb->>'bonus' from _dl where k = 'f_claim') = '0');
select supabase_tests.check('female → tanpa baris ledger daily_login',
  not exists(select 1 from public.coin_ledger
          where user_id = 'd0c1e000-0000-4000-8000-0000000000b2'
            and type = 'daily_login'));

-- ── 7. Kill-switch: points_enabled=false → tanpa kredit ──
update public.app_settings set points_enabled = false where id = 'global';
insert into _dl values ('rows_before', (select count(*)::text from public.coin_ledger
  where user_id = 'd0c1e000-0000-4000-8000-0000000000b1' and type = 'daily_login'));
update public.profiles set last_login_date = null, login_streak = 0
 where id = 'd0c1e000-0000-4000-8000-0000000000b1';
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000b1', true);
insert into _dl values ('off_claim', public.daily_login_bonus()::text);
select supabase_tests.check('points_enabled=false → bonus 0',
  (select v::jsonb->>'bonus' from _dl where k = 'off_claim') = '0');
select supabase_tests.check('points_enabled=false → jumlah baris tetap',
  (select count(*) from public.coin_ledger
    where user_id = 'd0c1e000-0000-4000-8000-0000000000b1'
      and type = 'daily_login')
  = (select v::int from _dl where k = 'rows_before'));
update public.app_settings set points_enabled = true where id = 'global';

-- ── 8. get_user_missions memuat data grid sign-in ──
-- (seksi 7 menyalakan gate TANPA mengubah profil → streak 0, last_date null)
insert into _dl values ('missions',
  public.get_user_missions('d0c1e000-0000-4000-8000-0000000000b1')::text);
select supabase_tests.check('get_user_missions → gender male + streak 0 + last_date null',
  (select v::jsonb->>'gender' from _dl where k = 'missions') = 'male'
  and (select v::jsonb->>'login_streak' from _dl where k = 'missions') = '0'
  and (select v::jsonb->>'last_login_date' from _dl where k = 'missions') is null);

-- ── 9. Misi per-gender: nyonya_1000 hanya untuk female ──
select supabase_tests.check('male → TANPA misi nyonya_1000',
  not exists(
    select 1 from jsonb_array_elements(
      (select v::jsonb->'main' from _dl where k = 'missions')) x
    where x->>'mission_key' = 'nyonya_1000'));
select set_config('request.jwt.claim.sub', 'd0c1e000-0000-4000-8000-0000000000b2', true);
insert into _dl values ('missions_f',
  public.get_user_missions('d0c1e000-0000-4000-8000-0000000000b2')::text);
select supabase_tests.check('female → misi nyonya_1000 ADA, judul tanpa suffix',
  exists(
    select 1 from jsonb_array_elements(
      (select v::jsonb->'main' from _dl where k = 'missions_f')) x
    where x->>'mission_key' = 'nyonya_1000'
      and x->>'title' = 'Misi Nyonya'));

-- ── 10. Progres nyonya = saldo earned NET (withdrawable) ──
-- Female B: 700 kredit → 700/1000 belum selesai; tambah 400 → penuh.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
  values ('d0c1e000-0000-4000-8000-0000000000b2', 'earned', 'call_video_income', 700, 'dl-nyonya');
insert into _dl values ('missions_f2',
  public.get_user_missions('d0c1e000-0000-4000-8000-0000000000b2')::text);
select supabase_tests.check('nyonya: 700 kredit → progress 700, belum selesai',
  exists(
    select 1 from jsonb_array_elements(
      (select v::jsonb->'main' from _dl where k = 'missions_f2')) x
    where x->>'mission_key' = 'nyonya_1000'
      and (x->>'progress')::int = 700
      and (x->>'is_completed')::boolean = false));
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
  values ('d0c1e000-0000-4000-8000-0000000000b2', 'earned', 'call_video_income', 400, 'dl-nyonya');
insert into _dl values ('missions_f3',
  public.get_user_missions('d0c1e000-0000-4000-8000-0000000000b2')::text);
select supabase_tests.check('nyonya: total 1100 → progress cap 1000 + selesai',
  exists(
    select 1 from jsonb_array_elements(
      (select v::jsonb->'main' from _dl where k = 'missions_f3')) x
    where x->>'mission_key' = 'nyonya_1000'
      and (x->>'progress')::int = 1000
      and (x->>'is_completed')::boolean = true));

-- Progres = saldo earned NET: kredit bucket lain TIDAK dihitung, dan
-- pengeluaran earned (belanja/withdraw) menurunkan progres.
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
  values ('d0c1e000-0000-4000-8000-0000000000b2', 'bonus', 'signup', 5000, 'dl-nyonya');
insert into _dl values ('missions_f4',
  public.get_user_missions('d0c1e000-0000-4000-8000-0000000000b2')::text);
select supabase_tests.check('nyonya: kredit bonus +5000 TIDAK menambah progres',
  exists(
    select 1 from jsonb_array_elements(
      (select v::jsonb->'main' from _dl where k = 'missions_f4')) x
    where x->>'mission_key' = 'nyonya_1000'
      and (x->>'progress')::int = 1000
      and (x->>'is_completed')::boolean = true));
insert into public.coin_ledger (user_id, bucket, type, amount, ref_id)
  values ('d0c1e000-0000-4000-8000-0000000000b2', 'earned', 'withdraw', -600, 'dl-nyonya');
insert into _dl values ('missions_f5',
  public.get_user_missions('d0c1e000-0000-4000-8000-0000000000b2')::text);
select supabase_tests.check('nyonya: withdraw -600 → progres turun 500, batal selesai',
  exists(
    select 1 from jsonb_array_elements(
      (select v::jsonb->'main' from _dl where k = 'missions_f5')) x
    where x->>'mission_key' = 'nyonya_1000'
      and (x->>'progress')::int = 500
      and (x->>'is_completed')::boolean = false));

select set_config('request.jwt.claim.sub', '', true);
select supabase_tests.report() as result;
rollback;
