-- ============================================================
-- Soft gate akun anon via app_settings.require_registration (Opsi 1).
--
-- Saat toggle OFF (default): SEMUA perilaku identik dengan sekarang.
-- Saat toggle ON:
--   - READ tetap terbuka  → anon existing masih browsing/lurk.
--   - WRITE diblokir      → chat room, chat pribadi, post, dan
--     pembuatan profil anon baru ditolak (RLS).
--   - BYPASS              → akun dummy (admin_dummy_uids) & admin
--     zunixe@gmail.com tetap full akses.
--
-- Helper cek profiles.is_registered (bukan claim JWT): anon selalu
-- is_registered=false → blocked; registered → lolos; anon yang upgrade
-- ke email/Google (uid tetap) → markRegistered set is_registered=true
-- → lolos otomatis. Anon tanpa row profile (belum entry) → blocked.
-- ============================================================

-- 1) Helper: boleh write?
create or replace function public._anon_write_ok()
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    not coalesce(
      (select require_registration from public.app_settings where id = 'global'),
      false)
  or auth.uid() in (select du from public.admin_dummy_uids() du)
  or coalesce(auth.email(), '') = 'zunixe@gmail.com'
  or coalesce((select is_registered from public.profiles where id = auth.uid()), false),
  false)
$fn$;

revoke execute on function public._anon_write_ok() from public, anon;
grant execute on function public._anon_write_ok() to authenticated;

-- 2) RLS INSERT: tambahkan guard anon pada with_check existing.
-- profiles — profiles_insert_own
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles
for insert to public
with check ((auth.uid() = id) and public._anon_write_ok());

-- messages — messages_insert
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert"
on public.messages
for insert to public
with check (((auth.uid() = sender_id) AND ((NOT (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = messages.room_id) AND (r.is_private = true))))) OR (EXISTS ( SELECT 1
   FROM room_members m
  WHERE ((m.room_id = messages.room_id) AND (m.user_id = auth.uid())))))) and public._anon_write_ok());

-- private_messages — private_messages_insert
drop policy if exists "private_messages_insert" on public.private_messages;
create policy "private_messages_insert"
on public.private_messages
for insert to public
with check (((auth.uid() = sender_id) AND (EXISTS ( SELECT 1
   FROM private_chats pc
  WHERE ((pc.chat_id = private_messages.chat_id) AND (auth.uid() = ANY (pc.participants))))) AND (NOT (EXISTS ( SELECT 1
   FROM (blocks b
     JOIN private_chats pc ON ((pc.chat_id = private_messages.chat_id)))
  WHERE ((b.blocked_id = auth.uid()) AND (b.blocker_id = ANY (pc.participants)) AND (b.blocker_id <> auth.uid())))))) and public._anon_write_ok());

-- posts — posts_insert_own
drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own"
on public.posts
for insert to public
with check ((auth.uid() = author_id) and public._anon_write_ok());

-- 3) Trigger guard untuk write path yang lewat RPC security definer
--    (RLS tidak berlaku di dalamnya). BEFORE INSERT di tabel target —
--    berlaku untuk RPC maupun insert langsung.
--
--    Tabel: post_likes (toggle_post_like), post_comments
--    (add_post_comment), post_shares (share_post), posts (create_post —
--    sudah ada RLS, trigger ini lapis kedua).
--
--    share_post & boost_post hanya UPDATE counter/posts (bukan insert
--    baris) — keduanya sudah butuh profile (me is null guard) dan
--    poin/registered di jalurnya; share counter anon tak berbahaya.
--    Konsistensi: boost_post sudah registered-only via points.

create or replace function public._anon_gate_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  return new;
end;
$fn$;

drop trigger if exists anon_gate_posts on public.posts;
create trigger anon_gate_posts
before insert on public.posts
for each row execute function public._anon_gate_insert();

drop trigger if exists anon_gate_post_likes on public.post_likes;
create trigger anon_gate_post_likes
before insert on public.post_likes
for each row execute function public._anon_gate_insert();

drop trigger if exists anon_gate_post_comments on public.post_comments;
create trigger anon_gate_post_comments
before insert on public.post_comments
for each row execute function public._anon_gate_insert();

drop trigger if exists anon_gate_post_shares on public.post_shares;
create trigger anon_gate_post_shares
before insert on public.post_shares
for each row execute function public._anon_gate_insert();
