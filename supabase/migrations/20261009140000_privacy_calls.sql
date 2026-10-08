-- ============================================================
-- Privasi PANGGILAN (call & video call).
--
-- LATAR: tabel `calls` sebelumnya TIDAK punya batasan privasi — siapa pun
-- (yang lolos gate anon/dummy) bisa menelepon siapa saja. Fitur ini
-- menambah setelan "Panggilan" (satu setelan untuk audio + video) memakai
-- mekanisme privasi yang SUDAH ada (6 opsi + exclusions).
--
-- YANG DIUBAH (salin PERSIS dari live @20261006040000 + tambahan 'call'):
--   1. profiles: +kolom call_visibility (default 'everyone').
--   2. CHECK profiles_privacy_visibility_check: +call_visibility
--      (sekalian masukkan leaderboard_visibility yang belum masuk di live).
--   3. CHECK profile_privacy_exclusions_field_check: +'call'.
--   4. update_privacy_settings: +param p_call (+ validasi + 'only').
--   5. my_privacy_settings: +'call'.
--   6. privacy_can_view: mapping field 'call' → call_visibility.
--   7. replace_privacy_exclusions: +'call' di whitelist field.
--   8. RLS calls_insert: +public.privacy_can_view(callee_id, 'call', auth.uid()).
--
-- ANON/DUMMY sebagai CALLEE: TIDAK dibatasi — default 'everyone' mengalir
-- apa adanya (mereka tak punya UI privasi). Gate anon/dummy di sisi CALLER
-- (toggle call_anon_enabled) tetap seperti sekarang.
--
-- menyentuh: privacy_can_view (tidak FROZEN, tapi diganti lintas-migrasi).
--
-- CARA APPLY: supabase db push / Management API. Idempotent.
-- ============================================================

-- ── 1) Kolom call_visibility ──
alter table public.profiles
  add column if not exists call_visibility text not null default 'everyone';

-- ── 2) CHECK visibility: 6 field (termasuk call + leaderboard) ──
alter table public.profiles drop constraint if exists profiles_privacy_visibility_check;
alter table public.profiles
  add constraint profiles_privacy_visibility_check check (
    presence_visibility      = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
    and last_seen_visibility = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
    and profile_photo_visibility = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
    and about_visibility     = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
    and story_visibility     = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
    and leaderboard_visibility = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
    and call_visibility      = any (array['everyone','everyone_except','friends','friends_except','only','nobody'])
  );

-- ── 3) CHECK exclusions: +'call' ──
alter table public.profile_privacy_exclusions
  drop constraint if exists profile_privacy_exclusions_field_check; -- SAFE: ganti isi CHECK (tambah 'call'), tidak mengubah data
alter table public.profile_privacy_exclusions
  add constraint profile_privacy_exclusions_field_check
  check (field = any (array['presence','last_seen','profile_photo','about','story','leaderboard','call']));

-- ── 4) update_privacy_settings: +p_call ──
-- DROP versi 7-arg lama (tanpa p_call) supaya tidak jadi OVERLOAD ambigu.
drop function if exists public.update_privacy_settings(text, text, text, text, text, boolean, text); -- SAFE: diganti versi 8-arg (+p_call) di bawah
create or replace function public.update_privacy_settings(
  p_presence text default null,
  p_last_seen text default null,
  p_profile_photo text default null,
  p_about text default null,
  p_story text default null,
  p_read_receipts boolean default null,
  p_leaderboard text default null,
  p_call text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_allowed text[] := array['everyone','everyone_except','friends','friends_except','only','nobody'];
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_presence is not null and not (p_presence = any(v_allowed)) then
    raise exception 'Invalid presence visibility';
  end if;
  if p_last_seen is not null and not (p_last_seen = any(v_allowed)) then
    raise exception 'Invalid last seen visibility';
  end if;
  if p_profile_photo is not null and not (p_profile_photo = any(v_allowed)) then
    raise exception 'Invalid profile photo visibility';
  end if;
  if p_about is not null and not (p_about = any(v_allowed)) then
    raise exception 'Invalid about visibility';
  end if;
  if p_story is not null and not (p_story = any(v_allowed)) then
    raise exception 'Invalid story visibility';
  end if;
  if p_leaderboard is not null and not (p_leaderboard = any(v_allowed)) then
    raise exception 'Invalid leaderboard visibility';
  end if;
  if p_call is not null and not (p_call = any(v_allowed)) then
    raise exception 'Invalid call visibility';
  end if;

  if p_presence = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'presence') then
    raise exception 'only requires at least one person';
  end if;
  if p_last_seen = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'last_seen') then
    raise exception 'only requires at least one person';
  end if;
  if p_profile_photo = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'profile_photo') then
    raise exception 'only requires at least one person';
  end if;
  if p_about = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'about') then
    raise exception 'only requires at least one person';
  end if;
  if p_story = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'story') then
    raise exception 'only requires at least one person';
  end if;
  if p_leaderboard = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'leaderboard') then
    raise exception 'only requires at least one person';
  end if;
  if p_call = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'call') then
    raise exception 'only requires at least one person';
  end if;

  update profiles set
    presence_visibility = coalesce(p_presence, presence_visibility),
    last_seen_visibility = coalesce(p_last_seen, last_seen_visibility),
    profile_photo_visibility = coalesce(p_profile_photo, profile_photo_visibility),
    about_visibility = coalesce(p_about, about_visibility),
    story_visibility = coalesce(p_story, story_visibility),
    leaderboard_visibility = coalesce(p_leaderboard, leaderboard_visibility),
    call_visibility = coalesce(p_call, call_visibility),
    read_receipts_enabled = coalesce(p_read_receipts, read_receipts_enabled)
  where id = auth.uid();
  return public.my_privacy_settings();
end;
$function$;

-- ── 5) my_privacy_settings: +'call' ──
create or replace function public.my_privacy_settings()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'presence', coalesce(presence_visibility, 'everyone'),
    'last_seen', coalesce(last_seen_visibility, 'everyone'),
    'profile_photo', coalesce(profile_photo_visibility, 'everyone'),
    'about', coalesce(about_visibility, 'everyone'),
    'story', coalesce(story_visibility, 'everyone'),
    'leaderboard', coalesce(leaderboard_visibility, 'everyone'),
    'call', coalesce(call_visibility, 'everyone'),
    'read_receipts', coalesce(read_receipts_enabled, true),
    'exclusions', coalesce((select jsonb_object_agg(field, ids) from (
      select field, jsonb_agg(excluded_uid) as ids
      from profile_privacy_exclusions
      where owner_id = auth.uid()
      group by field
    ) x), '{}'::jsonb)
  )
  from profiles where id = auth.uid();
$function$;

-- ── 6) privacy_can_view: +'call' (salib PERSIS dari live + 1 cabang) ──
create or replace function public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid default auth.uid())
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

  if coalesce((select privacy_bypass_enabled from public.app_settings where id = 'global'), false)
     and coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    return true;
  end if;

  -- Foto profil: mitra chat private boleh saling lihat. Hanya profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1 from public.private_chats c
    where c.participants @> array[p_owner, p_viewer]::uuid[]
  ) then
    return true;
  end if;

  -- Foto profil: anggota GRUP/room sama boleh saling lihat. Hanya profile_photo.
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
    when 'leaderboard' then leaderboard_visibility
    when 'call' then call_visibility
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

  if v_vis = 'everyone_except' then
    return not v_excluded;
  end if;

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

-- ── 7) replace_privacy_exclusions: +'call' ──
create or replace function public.replace_privacy_exclusions(p_field text, p_uids uuid[])
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_field not in ('presence','last_seen','profile_photo','about','story','leaderboard','call') then
    raise exception 'Invalid privacy field';
  end if;
  delete from profile_privacy_exclusions where owner_id = auth.uid() and field = p_field;
  insert into profile_privacy_exclusions(owner_id, excluded_uid, field)
  select auth.uid(), x, p_field from unnest(coalesce(p_uids, '{}'::uuid[])) x
  where x <> auth.uid()
  on conflict do nothing;
  return public.my_privacy_settings();
end;
$function$;

-- ── 8) RLS calls_insert: +cegah call ke callee yang menolak ──
-- gate lama dipertahankan PERSIS (admin / registered / anon+dummy bila toggle ON)
-- + public.privacy_can_view(callee_id, 'call', auth.uid()).
drop policy if exists calls_insert on public.calls; -- SAFE: ganti definisi policy insert calls (tambah cek privacy callee), bukan mencabut akses
create policy calls_insert on public.calls -- SAFE: ganti definisi policy insert calls (tambah cek privacy callee), gate anon/dummy tetap
  for insert to authenticated
  with check (
    auth.uid() = caller_id
    and public.privacy_can_view(callee_id, 'call', auth.uid())
    and (
      -- Admin selalu boleh.
      coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
      -- User terdaftar (bukan sesi dummy) selalu boleh.
      or (
        coalesce((select is_registered from public.profiles where id = auth.uid()), false)
        and not exists (
          select 1 from public.admin_dummy_uids() du where du = auth.uid()
        )
      )
      -- Anon & dummy: hanya bila toggle admin ON.
      or (
        coalesce((select call_anon_enabled from public.app_settings where id = 'global'), false)
        and (
          auth.uid() in (select du from public.admin_dummy_uids() du)
          or coalesce((select is_registered from public.profiles where id = auth.uid()), false) = false
        )
      )
    )
  );
