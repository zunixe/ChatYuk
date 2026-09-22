-- ============================================================
-- Privacy hardening: tutup kebocoran via REST langsung.
--
-- LATAR (audit 2026-09-22):
--   RLS `profiles_select` = USING(true) dan `user_photos_select` = true,
--   sehingga kolom yang MASIH ter-grant SELECT ke anon/authenticated bisa
--   dibaca siapa pun TANPA menghormati setting privasi:
--     - profiles.status, profiles.last_seen  → bypass presence/last_seen_visibility
--     - profiles.avatar                      → bypass profile_photo_visibility
--     - user_photos.photo                    → bypass paywall get_user_photos_access
--   (Kolom lat*/lon*/ip_address/email/fcm_token/about SUDAH tidak ter-grant —
--    di-hardening lebih awal. Tidak disentuh di sini.)
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
--   Lihat supabase/migrations/APPLIED_VIA_API.md.
--
-- STRATEGI:
--   1) Sediakan RPC ber-privacy sebagai SATU-SATUNYA jalur baca kolom tsb:
--        - presence_for(uid[])   → status/last_seen/avatar ber-privacy
--        - avatar_for(uid)       → avatar ber-privacy (1 uid)
--        - my_photos()           → foto galeri milik sendiri (jalur aman)
--      (get_user_photos_access sudah ada & ber-privacy — tidak diubah.)
--   2) REVOKE SELECT kolom sensitif dari anon + authenticated.
--
-- CATATAN: fungsi security definer (get_online_users, nearby_users,
-- profile_public, get_user_photos_access, admin_*) tetap bisa baca kolom
-- (owner definer = pemilik tabel) → tidak terpengaruh revoke ini.
-- ============================================================

-- ── 1) RPC presence ber-privacy ────────────────────────────────────────────
-- Ganti fungsi helper client yang dulu baca profiles mentah (fast-path &
-- fallback di chat_service_presence.dart). Terapkan presence/last_seen/
-- profile_photo_visibility + blokir + invisible.
create or replace function public.presence_for(p_uids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  invisible_uid uuid;
  arr jsonb;
begin
  -- Invisible (mis. admin mode) → hilangkan dari hasil, konsisten dgn
  -- get_online_users yang memfilter invisible lewat status.
  select s.invisible_admin_uid into invisible_uid
    from public.app_settings s where s.id = 'global';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',        p.id,
    'nickname',  p.nickname,
    'gender',    p.gender,
    'age',       p.age,
    'country',   p.country,
    'city',      p.city,
    'is_registered', p.is_registered,
    'avatar',    case when public.privacy_can_view(p.id, 'profile_photo', me)
                      then p.avatar else '' end,
    'status',    case when public.privacy_can_view(p.id, 'presence', me)
                      then p.status else 'offline' end,
    'last_seen', case when public.privacy_can_view(p.id, 'last_seen', me)
                      then p.last_seen else null end
  )), '[]'::jsonb) into arr
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]))
    and p.id <> coalesce(me, '00000000-0000-0000-0000-000000000000'::uuid)
    and (invisible_uid is null or p.id <> invisible_uid)
    -- Hormati blokir dua arah (sama seperti get_online_users).
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    );

  return arr;
end;
$fn$;

revoke execute on function public.presence_for(uuid[]) from public, anon;
grant execute on function public.presence_for(uuid[]) to authenticated;

-- ── 2) RPC avatar ber-privacy (1 uid) ──────────────────────────────────────
create or replace function public.avatar_for(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = public
as $fn$
  select case
    when public.privacy_can_view(p_uid, 'profile_photo', auth.uid())
      then coalesce(p.avatar, '')
    else '' end
  from public.profiles p
  where p.id = p_uid;
$fn$;

revoke execute on function public.avatar_for(uuid) from public, anon;
grant execute on function public.avatar_for(uuid) to authenticated;

-- ── 2b) RPC avatar batch ber-privacy ───────────────────────────────────────
-- Dipakai prefetch daftar user (leaderboard/social) — 1 query ganti N+1.
create or replace function public.avatars_for(p_uids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'avatar', case when public.privacy_can_view(p.id, 'profile_photo', auth.uid())
                   then coalesce(p.avatar, '') else '' end
  )), '[]'::jsonb)
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]));
$fn$;

revoke execute on function public.avatars_for(uuid[]) from public, anon;
grant execute on function public.avatars_for(uuid[]) to authenticated;

-- ── 3) RPC foto galeri milik sendiri ───────────────────────────────────────
-- Jalur aman untuk `getPhotos(own)` setelah `user_photos.photo` di-revoke.
-- Hanya foto milik pemanggil; bentuk data SAMA dengan get_user_photos_access.
create or replace function public.my_photos()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  arr jsonb;
begin
  if me is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',         r.id,
    'unlocked',   true,
    'photo',      r.photo,
    'preview',    coalesce(r.photo_preview, ''),
    'created_at', r.created_at
  ) order by r.created_at asc), '[]'::jsonb) into arr
  from public.user_photos r where r.user_id = me;
  return arr;
end;
$fn$;

revoke execute on function public.my_photos() from public, anon;
grant execute on function public.my_photos() to authenticated;

-- ── 4) REVOKE kolom sensitif ───────────────────────────────────────────────
-- profiles: status + last_seen + avatar (dibaca lewat presence_for/avatar_for/
-- profile_public). share_location juga dicabut (boolean, bocorkan niat).
revoke select (status, last_seen, avatar, share_location)
  on public.profiles from anon, authenticated;

-- user_photos: photo asli (base64/path) → hanya lewat RPC ber-gating.
-- photo_preview tetap ter-grant (preview blur aman untuk listing).
-- CATATAN: user_photos punya TABLE-level SELECT grant (arwdDxtm) yang
-- menutupi revoke kolom → harus revoke table-level dulu, lalu re-grant
-- HANYA kolom aman.
revoke select on public.user_photos from anon, authenticated;
grant select (id, user_id, photo_preview, created_at)
  on public.user_photos to anon, authenticated;
