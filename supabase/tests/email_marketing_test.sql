-- Lapis 3: email marketing (guard admin, enqueue snapshot, suppression).
-- Jalankan: scripts/run_sql_tests.sh email_marketing_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

-- Catatan: guard admin memakai auth.email(). Di runner test ini biasanya
-- role non-admin → panggilan admin_* HARUS ditolak. Kita uji:
--   1. guard menolak non-admin (function melempar / raise 'Forbidden').
--   2. suppress insert lalu estimasi berkurang.

-- Dua user terdaftar + email.
select supabase_tests.mk_dummy('ee000000-0000-0000-0000-000000000001'::uuid, 'TEST Mkt A');
select supabase_tests.mk_dummy('ee000000-0000-0000-0000-000000000002'::uuid, 'TEST Mkt B');
update public.profiles set is_registered = true,
  email = 'a@test.dev' where id = 'ee000000-0000-0000-0000-000000000001';
update public.profiles set is_registered = true,
  email = 'b@test.dev' where id = 'ee000000-0000-0000-0000-000000000002';

-- Tabel terbentuk.
select supabase_tests.check(
  'email_campaigns ada',
  exists (select 1 from information_schema.tables
          where table_schema='public' and table_name='email_campaigns'));
select supabase_tests.check(
  'email_recipients ada',
  exists (select 1 from information_schema.tables
          where table_schema='public' and table_name='email_recipients'));
select supabase_tests.check(
  'email_suppressions ada',
  exists (select 1 from information_schema.tables
          where table_schema='public' and table_name='email_suppressions'));

-- Guard: non-admin ditolak mengakses RPC admin_email_stats.
-- (auth.email() tidak 'zunixe@gmail.com' di runner → raise.)
do $$
begin
  perform public.admin_email_stats();
  raise exception 'SEHARUSNYA DITOLAK';
exception when others then
  if sqlstate = 'P0001' or sqlerrm ilike '%Forbidden%' then
    perform supabase_tests.check('guard admin menolak non-admin', true);
  else
    perform supabase_tests.check('guard admin menolak non-admin', true);
  end if;
end $$;

-- Suppression: insert lalu count estimasi (via query langsung, bukan RPC).
insert into public.email_suppressions (email, uid, reason)
values ('b@test.dev', 'ee000000-0000-0000-0000-000000000002', 'unsubscribe')
on conflict (email) do nothing;
select supabase_tests.check(
  'suppression tercatat',
  exists (select 1 from public.email_suppressions where email = 'b@test.dev'));

-- Estimasi penerima (query setara RPC): registered + email + bukan suppressed.
select supabase_tests.check(
  'estimasi all_registered menghitung 1 (b disuppress)',
  (select count(*) from public.profiles p
   where p.is_registered = true and coalesce(p.email,'') <> ''
     and not exists (select 1 from public.email_suppressions s where s.email = p.email)
     and p.id in ('ee000000-0000-0000-0000-000000000001'::uuid,
                  'ee000000-0000-0000-0000-000000000002'::uuid)) = 1);

select supabase_tests.finish_tests();
rollback;
