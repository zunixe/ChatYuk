-- ============================================================
-- Bypass privasi untuk admin (toggle di Admin > Global Setting).
--
-- Masalah: user mengunci profil (foto/status/last_seen/about/story hanya
-- teman) sehingga admin tidak bisa melihat mereka saat monitoring.
--
-- Fix: flag global `app_settings.privacy_bypass_enabled`. Bila ON *dan*
-- viewer = admin, `privacy_can_view()` return true untuk semua field.
-- User biasa TIDAK terdampak (flag saja tidak cukup — harus email admin).
-- Default OFF. Tidak menyentuh fungsi FROZEN / RLS tabel bersama.
-- ============================================================

alter table public.app_settings
  add column if not exists privacy_bypass_enabled boolean not null default false;

create or replace function public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_vis text;
  v_friend boolean;
  v_excluded boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

  -- Bypass admin: flag ON + viewer admin → semua field terlihat.
  -- (auth.email() = pemanggil, walau SECURITY DEFINER.)
  if coalesce((select privacy_bypass_enabled from public.app_settings where id = 'global'), false)
     and coalesce(auth.email(), '') = 'zunixe@gmail.com' then
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

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  -- 'friends_except': hanya teman, kecuali yang masuk daftar.
  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end; $$;

-- Setter khusus (satu tujuan, guard admin). Baca via
-- admin_get_point_settings (return full to_jsonb(app_settings)).
create or replace function public.admin_set_privacy_bypass(p_enabled boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update public.app_settings
    set privacy_bypass_enabled = coalesce(p_enabled, false),
        updated_at = now()
    where id = 'global';
  return (select to_jsonb(a) from public.app_settings a where id = 'global');
end; $$;
