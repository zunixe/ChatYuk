-- Regresi presence & ghost mode (migrasi 20261027120000 + 20261027121000).
--
-- Mengunci 3 perilaku yang pernah rusak:
--   1) Ambang idle server 10 menit (dulu 4 menit = SAMA dengan interval
--      heartbeat klien → race → user aktif ikut jadi 'idle' lalu 'offline'
--      dan hilang dari daftar Online). Kasus live: "pornsex".
--   2) Ghost Mode (invisible berbayar) BENAR-BENAR menyembunyikan user dari
--      get_online_users (dulu tidak berefek sama sekali).
--   3) Admin bisa MELIHAT siapa yang sedang ghost (admin_ghost_users) —
--      dulu tidak ada sumber data → "kenapa di admin tidak tercatat".
--
-- Jalankan: scripts/run_sql_tests.sh presence_ghost_test.sql
-- Transaksional (begin/rollback) — data produksi tak berubah.
begin;
select supabase_tests.begin_tests();

-- Dua akun uji: satu normal, satu akan jadi ghost.
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000c1'::uuid, '[TEST] OnlineBiasa', 'online');
select supabase_tests.mk_dummy('d0c1e000-0000-4000-8000-0000000000c2'::uuid, '[TEST] GhostUser', 'online');

-- Pastikan keduanya "segar" (last_seen = now) dan privacy terbuka.
update public.profiles
   set last_seen = now(),
       presence_visibility = 'everyone',
       last_seen_visibility = 'everyone'
 where id in ('d0c1e000-0000-4000-8000-0000000000c1'::uuid,
              'd0c1e000-0000-4000-8000-0000000000c2'::uuid);

-- ── 1) Ambang idle server = 10 menit ───────────────────────────────────────
select supabase_tests.check(
  'presence_idle_tick default = 10 menit (2.5x heartbeat 4 mnt)',
  pg_get_function_arguments('public.presence_idle_tick(interval)'::regprocedure)
    like '%00:10:00%'
);

-- PENTING: `presence_idle_tick` SENGAJA mengecualikan akun dummy (presence
-- dummy diatur ai_presence_tick/admin). `mk_dummy` memasukkan baris ke
-- dummy_accounts, jadi untuk menguji jalur user ASLI kita lepaskan dulu.
delete from public.dummy_accounts
 where uid = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid;

-- User dengan last_seen 6 menit (masih di bawah ambang) TIDAK boleh jadi idle.
update public.profiles
   set status = 'online', last_seen = now() - interval '6 minutes'
 where id = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid;
select public.presence_idle_tick(interval '10 minutes');
select supabase_tests.check(
  'last_seen 6 mnt TETAP online (tidak ditendang ke idle)',
  (select status from public.profiles
    where id = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid) = 'online'
);

-- User dengan last_seen 12 menit HARUS jadi idle.
update public.profiles
   set status = 'online', last_seen = now() - interval '12 minutes'
 where id = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid;
select public.presence_idle_tick(interval '10 minutes');
select supabase_tests.check(
  'last_seen 12 mnt jadi idle',
  (select status from public.profiles
    where id = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid) = 'idle'
);

-- ── 2) Ghost mode menyembunyikan dari get_online_users ────────────────────
-- Kembalikan user uji ke online segar.
update public.profiles
   set status = 'online', last_seen = now()
 where id in ('d0c1e000-0000-4000-8000-0000000000c1'::uuid,
              'd0c1e000-0000-4000-8000-0000000000c2'::uuid);

-- Tanpa ghost: keduanya muncul.
select supabase_tests.check(
  'tanpa ghost: 2 user uji muncul di get_online_users',
  (select count(*) from jsonb_array_elements(public.get_online_users(null, 1000)) e
    where e->>'nickname' like '[TEST]%') = 2
);

-- Aktifkan ghost untuk GhostUser.
insert into public.ghost_mode_active(user_id, expires_at)
values ('d0c1e000-0000-4000-8000-0000000000c2'::uuid, now() + interval '1 day')
on conflict (user_id) do update set expires_at = excluded.expires_at;

select supabase_tests.check(
  'ghost aktif: GhostUser HILANG dari get_online_users',
  (select count(*) from jsonb_array_elements(public.get_online_users(null, 1000)) e
    where e->>'nickname' ilike '%GhostUser%') = 0
);

select supabase_tests.check(
  'ghost aktif: user biasa TETAP muncul',
  (select count(*) from jsonb_array_elements(public.get_online_users(null, 1000)) e
    where e->>'nickname' ilike '%OnlineBiasa%') = 1
);

-- ── 3) Admin bisa MELIHAT user ghost ──────────────────────────────────────
select supabase_tests.check(
  'admin_ghost_users menampilkan GhostUser',
  (select count(*) from jsonb_array_elements(public.admin_ghost_users()) e
    where e->>'nickname' ilike '%GhostUser%') = 1
);

-- ── 3b) JALUR BOCOR: realtime & profile_public (20261027122000) ───────────
-- Trigger memaksa status tersimpan tetap 'offline' selama ghost aktif →
-- payload postgres_changes yang dibaca klien otomatis 'offline'.
update public.profiles
   set status = 'online', last_seen = now()
 where id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid;

select supabase_tests.check(
  'ghost aktif: heartbeat "online" DIPAKSA jadi offline (anti-bocor realtime)',
  (select status from public.profiles
    where id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid) = 'offline'
);

select supabase_tests.check(
  'ghost aktif: profile_public mengembalikan status offline',
  (public.profile_public('d0c1e000-0000-4000-8000-0000000000c2'::uuid)->>'status')
    = 'offline'
);

select supabase_tests.check(
  'ghost aktif: presence_for mengembalikan status offline',
  (select e->>'status' from jsonb_array_elements(
      public.presence_for(array['d0c1e000-0000-4000-8000-0000000000c2'::uuid])) e) = 'offline'
);

-- ── 4) Ghost kedaluwarsa → muncul lagi otomatis ───────────────────────────
update public.ghost_mode_active
   set expires_at = now() - interval '1 minute'
 where user_id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid;

-- Tirukan heartbeat berikutnya: status 'offline' selama ghost memang sengaja
-- dipaksa (lihat trigger), jadi user baru kembali online saat heartbeat
-- pertama SETELAH ghost kedaluwarsa. Ini perilaku yang diinginkan.
update public.profiles
   set status = 'online', last_seen = now()
 where id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid;

select supabase_tests.check(
  'ghost kedaluwarsa: user muncul lagi di get_online_users',
  (select count(*) from jsonb_array_elements(public.get_online_users(null, 1000)) e
    where e->>'nickname' ilike '%GhostUser%') = 1
);

select supabase_tests.check(
  'ghost kedaluwarsa: tidak lagi tampil di admin_ghost_users',
  (select count(*) from jsonb_array_elements(public.admin_ghost_users()) e
    where e->>'nickname' ilike '%GhostUser%') = 0
);

-- Trigger TIDAK boleh mengunci status selamanya: setelah kedaluwarsa,
-- heartbeat 'online' harus diterima kembali apa adanya.
update public.profiles
   set status = 'online', last_seen = now()
 where id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid;

select supabase_tests.check(
  'ghost kedaluwarsa: status online diterima lagi (trigger lepas)',
  (select status from public.profiles
    where id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid) = 'online'
);

-- ── 5) Interaksi dengan invisible milik ADMIN ────────────────────────────
-- Ghost user-level dan invisible admin adalah dua mekanisme berbeda.
-- Bila keduanya aktif, 'invisible' (admin) yang menang — trigger ghost
-- dijalankan lebih dulu (alfabetis) lalu ditimpa trg_enforce_invisible.
insert into public.ghost_mode_active(user_id, expires_at)
values ('d0c1e000-0000-4000-8000-0000000000c1'::uuid, now() + interval '1 day')
on conflict (user_id) do update set expires_at = excluded.expires_at;

update public.app_settings
   set invisible_enabled = true,
       invisible_admin_uid = 'd0c1e000-0000-4000-8000-0000000000c1'
 where id = 'global';

update public.profiles
   set status = 'online'
 where id = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid;

select supabase_tests.check(
  'ghost + invisible admin: invisible menang',
  (select status from public.profiles
    where id = 'd0c1e000-0000-4000-8000-0000000000c1'::uuid) = 'invisible'
);

-- Kembalikan setting admin agar rollback bersih.
update public.app_settings
   set invisible_enabled = false, invisible_admin_uid = null
 where id = 'global';

-- ── 3c) JALUR BOCOR: nearby_users (20261027123000) ───────────────────────
-- nearby_users memakai filter presence yang sama dgn get_online_users; tanpa
-- klausa ghost, user ghost tetap terlihat di daftar Nearby.
-- Butuh lat/lon agar masuk kandidat radius.
update public.profiles
   set lat = -6.2000, lon = 106.8166, country = 'Indonesia'
 where id in ('d0c1e000-0000-4000-8000-0000000000c1'::uuid,
              'd0c1e000-0000-4000-8000-0000000000c2'::uuid);

-- Ghost aktif lagi untuk GhostUser.
insert into public.ghost_mode_active(user_id, expires_at)
values ('d0c1e000-0000-4000-8000-0000000000c2'::uuid, now() + interval '1 day')
on conflict (user_id) do update set expires_at = excluded.expires_at;

update public.profiles
   set status = 'online', last_seen = now()
 where id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid;

select supabase_tests.check(
  'nearby_users: definisi memeriksa ghost_mode_active',
  position('ghost_mode_active' in
    pg_get_functiondef('public.nearby_users(double precision,integer,integer)'::regprocedure)) > 0
);

-- Bersihkan ghost agar sisa test tidak terpengaruh.
delete from public.ghost_mode_active
 where user_id = 'd0c1e000-0000-4000-8000-0000000000c2'::uuid;

select supabase_tests.report() as result;
rollback;
