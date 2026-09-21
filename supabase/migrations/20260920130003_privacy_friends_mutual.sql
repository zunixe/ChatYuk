-- ============================================================
-- PERBAIKAN privacy "teman" — 2 bug nyata:
--
-- 1) SEMANTIK 'except' SALAH.
--    Sebelumnya: 'except' = "semua orang KECUALI daftar" → non-teman ikut
--    bisa melihat, padahal maksud user adalah "TEMAN saya kecuali mereka".
--    Sekarang: 'except' = teman AND tidak masuk daftar pengecualian.
--
-- 2) DEFINISI TEMAN BEDA dengan daftar teman di aplikasi.
--    Aplikasi (SocialProvider.friends, filter "Teman" di chat, profil)
--    memakai MUTUAL FOLLOW (`social_list('friends')`). Privacy memakai
--    friend_requests 'accepted' → daftar di picker bisa beda/kosong walau
--    app menampilkan teman. Sekarang privacy memakai definisi yang SAMA
--    (mutual follow) supaya pilihan pengecualian selalu cocok.
--
-- Catatan: `_are_friends` (friend_requests accepted) TETAP dipakai untuk
-- visibility story — tidak diubah di sini.
-- ============================================================

-- Helper: teman = mutual follow (definisi yang sama dengan social_list).
create or replace function public._privacy_are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (
    select 1
    from public.follows f1
    join public.follows f2
      on f1.followee_id = f2.follower_id
     and f1.follower_id = f2.followee_id
    where f1.follower_id = a
      and f1.followee_id = b
  );
$fn$;

-- Helper: apakah field ini boleh dilihat (dipakai get_online_users,
-- nearby_users, profile_public, story_slides, dan RPC lain).
create or replace function public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_vis text;
  v_friend boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

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

  -- friends & except sama-sama berbasis TEMAN; 'except' hanya mengecualikan
  -- sebagian teman, BUKAN membuka ke semua orang.
  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  if v_vis = 'except' then
    return not exists (
      select 1 from public.profile_privacy_exclusions e
      where e.owner_id = p_owner
        and e.excluded_uid = p_viewer
        and e.field = p_field
    );
  end if;

  return true; -- 'friends'
end;
$fn$;

-- Daftar teman (mutual follow) untuk picker "Teman kecuali" — sama persis
-- dengan teman yang berpengaruh di privacy_can_view.
create or replace function public.privacy_friends()
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'uid', p.id,
        'nickname', p.nickname,
        'avatar', p.avatar,
        'gender', p.gender,
        'is_registered', p.is_registered
      )
      order by p.nickname
    ),
    '[]'::jsonb
  )
  from public.profiles p
  where p.id <> auth.uid()
    and public._privacy_are_friends(auth.uid(), p.id);
$fn$;

revoke execute on function public.privacy_friends() from public, anon;
grant execute on function public.privacy_friends() to authenticated;
revoke execute on function public.privacy_can_view(uuid, text, uuid) from public, anon;
grant execute on function public.privacy_can_view(uuid, text, uuid) to authenticated;
