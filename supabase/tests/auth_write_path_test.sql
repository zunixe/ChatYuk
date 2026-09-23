-- Lapis 3: kontrak tulis REGISTRASI vs PRIVASI (dua arah, insiden anon 2026-09-22).
-- Insiden: REVOKE SELECT di profiles.status/avatar/last_seen merusak
-- registerProfile() (upsert butuh SELECT di semua kolom tertulis → 42501),
-- padahal revoke itu NEEDED untuk privasi. Kedua arah dikunci di SATU file
-- supaya AI berikutnya tidak bisa "membetulkan" satu sisi sambil merusak
-- sisi lain (GRANT SELECT = buka privasi; REVOKE = matikan registrasi).
-- Pola tulis yang benar: upsert ignore-duplicates + PATCH (tanpa butuh SELECT).
-- Transaksional (BEGIN/ROLLBACK), tidak menyentuh data produksi.
begin;
select supabase_tests.begin_tests();

-- ── Arah PRIVASI: kolom sensitif tetap TANPA SELECT untuk anon/authenticated ──
select supabase_tests.check('status tanpa SELECT (anon+authenticated)',
  not has_column_privilege('anon', 'public.profiles', 'status', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'status', 'SELECT'));
select supabase_tests.check('avatar tanpa SELECT (anon+authenticated)',
  not has_column_privilege('anon', 'public.profiles', 'avatar', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'avatar', 'SELECT'));
select supabase_tests.check('last_seen tanpa SELECT (anon+authenticated)',
  not has_column_privilege('anon', 'public.profiles', 'last_seen', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'last_seen', 'SELECT'));
select supabase_tests.check('email/ip_address/fcm_token tanpa SELECT (anon+authenticated)',
  not has_column_privilege('anon', 'public.profiles', 'email', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'email', 'SELECT')
  and not has_column_privilege('anon', 'public.profiles', 'ip_address', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'ip_address', 'SELECT')
  and not has_column_privilege('anon', 'public.profiles', 'fcm_token', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'fcm_token', 'SELECT'));

-- ── Arah REGISTRASI: 12 kolom wajib tulis tetap INSERT+UPDATE untuk authenticated ──
-- (id,nickname,gender,age,country,city,status,avatar,is_registered,login_at,created_at,last_seen)
select supabase_tests.check('kolom registrasi punya INSERT (authenticated)',
  (select bool_and(has_column_privilege('authenticated', 'public.profiles', c, 'INSERT'))
   from (values ('id'),('nickname'),('gender'),('age'),('country'),('city'),
                ('status'),('avatar'),('is_registered'),('login_at'),
                ('created_at'),('last_seen')) as t(c)));
select supabase_tests.check('kolom registrasi punya UPDATE (authenticated)',
  (select bool_and(has_column_privilege('authenticated', 'public.profiles', c, 'UPDATE'))
   from (values ('id'),('nickname'),('gender'),('age'),('country'),('city'),
                ('status'),('avatar'),('is_registered'),('login_at'),
                ('created_at'),('last_seen')) as t(c)));

-- ── RLS insert-own masih mengizinkan anon mendaftar ──
select supabase_tests.check('policy profiles_insert_own ada (anulir = anon gagal daftar)',
  exists(
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
      and policyname = 'profiles_insert_own' and cmd = 'INSERT'
  ));

select supabase_tests.report() as result;
rollback;
