-- ============================================================
-- ChatYuk: HARDENING keamanan RLS
-- 1. profiles: sembunyikan ip_address & fcm_token dari akses publik
--    (app hanya UPDATE kolom ini, tidak pernah SELECT — aman).
--    Kolom publik dibatasi via column-level grant.
-- 2. rooms: INSERT/UPDATE hanya admin (zunixe@gmail.com).
--    SELECT tetap publik (room chat umum).
-- NOTE: user_photos SELECT tetap publik — fitur "lihat galeri user lain"
--       (user_info_screen) memang sengaja terbuka.
-- ============================================================

-- 1. profiles — column-level revoke (sembunyikan kolom sensitif)
revoke select on public.profiles from anon, authenticated;
grant select (id, nickname, gender, age, country, city, status, avatar, is_registered, login_at, created_at, last_seen, hashtags, points, email)
  on public.profiles to anon, authenticated;

-- 2. rooms — batasi insert/update ke admin
drop policy if exists rooms_insert on public.rooms;
drop policy if exists rooms_update on public.rooms;
create policy rooms_insert on public.rooms
  for insert with check ((auth.jwt() ->> 'email') = 'zunixe@gmail.com');
create policy rooms_update on public.rooms
  for update using ((auth.jwt() ->> 'email') = 'zunixe@gmail.com');
