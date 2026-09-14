-- menyentuh: (tidak ada fungsi frozen — hanya harness test)
-- Lapis 3: harness test SQL berbasis SELECT-returning.
--
-- KENAPA bukan pgTAP: driver Management API hanya mengembalikan baris hasil
-- query terakhir dan MEMBUANG RAISE NOTICE. pgTAP menulis tiap assert lewat
-- RAISE → tak terbaca dari jalur ini. Maka harness ini mengumpulkan hasil ke
-- tabel sementara, lalu `report()` mengembalikannya sebagai SATU baris JSON
-- yang bisa dibaca runner.
create schema if not exists supabase_tests;

-- Hasil dikumpulkan di tabel unlogged (aman, tak perlu transaksi panjang).
create table if not exists supabase_tests.results (
  id bigserial primary key,
  label text not null,
  ok boolean not null,
  detail text
);

-- Mulai sesi: kosongkan hasil.
create or replace function supabase_tests.begin_tests()
returns void language sql security definer set search_path = supabase_tests as $fn$
  truncate supabase_tests.results;
$fn$;

-- Catat assert.
create or replace function supabase_tests.check(
  p_label text, p_ok boolean, p_detail text default null
) returns void
language sql security definer
set search_path = supabase_tests
as $fn$
  insert into supabase_tests.results(label, ok, detail)
  values (p_label, coalesce(p_ok, false), p_detail);
$fn$;

-- Ringkasan akhir: SATU baris teks yang bisa dibaca runner.
create or replace function supabase_tests.report()
returns text
language sql security definer
set search_path = supabase_tests
as $fn$
  select format('TOTAL=%s PASS=%s FAIL=%s%s',
    count(*),
    count(*) filter (where ok),
    count(*) filter (where not ok),
    coalesce(string_agg(format(E'\nFAIL: %s (%s)', label, coalesce(detail,'')),
      '' order by id) filter (where not ok), ''))
  from supabase_tests.results;
$fn$;

-- Helper: bikin user auth + profile + dummy utk test.
create or replace function supabase_tests.mk_dummy(
  p_uid uuid, p_nickname text, p_status text default 'offline'
) returns void
language plpgsql security definer
set search_path = public
as $fn$
begin
  insert into auth.users (id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at, created_at, updated_at)
  values (p_uid, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', p_uid::text || '@test.local', '', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.profiles (id, nickname, gender, age, country, city,
    status, last_seen, is_registered, login_at, created_at)
  values (p_uid, p_nickname, 'male', 25, 'ID', 'Jakarta',
    p_status, now(), true, now(), now())
  on conflict (id) do update
    set nickname = excluded.nickname, status = excluded.status, last_seen = now();

  insert into public.dummy_accounts (uid, nickname, ai_enabled, ai_active_hours)
  values (p_uid, p_nickname, true, '[]'::jsonb)
  on conflict (uid) do update
    set ai_enabled = true, nickname = excluded.nickname;
end;
$fn$;

create or replace function supabase_tests.cleanup(p_uids uuid[])
returns void language plpgsql security definer set search_path = public as $fn$
begin
  delete from public.dummy_accounts where uid = any(p_uids);
  delete from public.profiles where id = any(p_uids);
  delete from auth.users where id = any(p_uids);
end;
$fn$;

revoke all on schema supabase_tests from public, anon, authenticated;
grant usage on schema supabase_tests to service_role;
grant all on all tables in schema supabase_tests to service_role;
grant execute on all functions in schema supabase_tests to service_role;
