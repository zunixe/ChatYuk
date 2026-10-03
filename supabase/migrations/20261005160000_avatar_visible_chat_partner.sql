-- ============================================================
-- Foto profil: mitra CHAT PRIVATE boleh saling lihat walau
-- `profile_photo_visibility='friends'`.
--
-- LATAR (2026-10-05): di list Pesan / header chat, avatar partner pakai
--   `avatar_for` → `privacy_can_view(profile_photo)`. Bila partner set
--   visibility 'friends' TAPI kalian bukan teman (baru chat), foto TIDAK
--   tampil (cuma inisial) — padahal kalian sedang mengobrol. Terbukti live:
--   user 'Tya' (visibility=friends) avatar-nya ada tapi tak muncul di list
--   chat viewer yang bukan temannya.
--
-- PERBAIKAN: `privacy_can_view` — untuk field `profile_photo`, bila viewer
--   dan owner berada di SATU private chat (participants @> [owner, viewer]),
--   kembalikan TRUE. Ini wajar: foto mitra obrolan terlihat (sudah saling
--   kontak). Field lain (presence/last_seen/about/story) TIDAK diubah.
--
-- Sumber `privacy_can_view` disalin PERSIS dari versi live + satu cabang
--   tambahan di awal (setelah cek owner/viewer). Bukan FROZEN.
-- CARA APPLY: Management API (1 statement create fn).
-- ============================================================

create or replace function public.privacy_can_view(
  p_owner uuid,
  p_field text,
  p_viewer uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_vis text;
  v_friend boolean;
  v_excluded boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

  -- Bypass admin: flag ON + viewer admin → semua field terlihat.
  if coalesce((select privacy_bypass_enabled from public.app_settings where id = 'global'), false)
     and coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    return true;
  end if;

  -- (BARU) Foto profil: mitra chat private boleh saling lihat (wajar —
  -- sudah saling berkontak). Hanya field profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1 from public.private_chats c
    where c.participants @> array[p_owner, p_viewer]::uuid[]
  ) then
    return true;
  end if;

  -- (BARU) Foto profil: anggota GRUP/room yang SAMA (room_members) boleh
  -- saling lihat — seusai konteks obrolan room. Hanya field profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1
      from public.room_members a
      join public.room_members b on b.room_id = a.room_id
     where a.user_id = p_owner and b.user_id = p_viewer
  ) then
    return true;
  end if;

  select case p_field
    when 'presence' then presence_visibility
    when 'last_seen' then last_seen_visibility
    when 'profile_photo' then profile_photo_visibility
    when 'about' then about_visibility
    when 'story' then story_visibility
    else 'nobody'
  end into v_vis
  from public.profiles where id = p_owner;

  v_vis := coalesce(v_vis, 'nobody');
  if v_vis = 'everyone' then return true; end if;
  if v_vis = 'nobody' then return false; end if;

  v_excluded := exists (
    select 1 from public.profile_privacy_exclusions e
    where e.owner_id = p_owner
      and e.excluded_uid = p_viewer
      and e.field = p_field
  );

  -- 'everyone_except': semua orang boleh, KECUALI yang masuk daftar.
  if v_vis = 'everyone_except' then
    return not v_excluded;
  end if;

  -- 'only': HANYA orang di daftar (daftar putih).
  if v_vis = 'only' then
    return v_excluded;
  end if;

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end; $function$;

-- Verifikasi setelah apply (butuh viewer yg ber-chat dgn owner):
--   select public.privacy_can_view('<owner>','profile_photo','<viewer>');
