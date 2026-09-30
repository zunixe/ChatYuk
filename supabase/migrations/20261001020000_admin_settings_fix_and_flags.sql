-- ============================================================
-- ChatYuk — Perbaiki admin_update_point_settings + feature flag control
--
-- BUG yang diperbaiki: migrasi 20260901080000_reengage_notif.sql men-replace
-- admin_update_point_settings dengan versi yang HANYA meng-update
-- reengage_enabled → semua field poin/tarif lain yang dikirim form admin
-- (bonus_*, cost_*, tarif call baru, dsb.) DIABAIKAN. Form Point Settings
-- admin sejak itu tidak benar-benar tersimpan. Di sini dikembalikan:
-- update SEMUA field + field tarif call/filter/nearby baru.
--
-- admin_get_point_settings sudah return to_jsonb(app_settings) penuh
-- (20260901080000) → field baru otomatis ikut, tidak perlu diubah.
--
-- Tambah: admin_set_feature_flag(p_feature, p_published) untuk tombol
-- "Publish" fitur dari panel admin (build adminProd → publish global).
--
-- admin_update_point_settings & admin_get_point_settings BUKAN fungsi
-- FROZEN. Idempotent (create or replace).
-- ============================================================

create or replace function public.admin_update_point_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    -- Foto
    photo_upload_reward    = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once      = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm      = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct = coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    -- Bonus lama (dipertahankan agar form tidak error; faucet sudah no-op)
    bonus_registered       = coalesce((p->>'bonus_registered')::int, bonus_registered),
    bonus_rated            = coalesce((p->>'bonus_rated')::int, bonus_rated),
    bonus_shared           = coalesce((p->>'bonus_shared')::int, bonus_shared),
    bonus_profile          = coalesce((p->>'bonus_profile')::int, bonus_profile),
    bonus_first_photo      = coalesce((p->>'bonus_first_photo')::int, bonus_first_photo),
    bonus_room_read        = coalesce((p->>'bonus_room_read')::int, bonus_room_read),
    bonus_new_chat         = coalesce((p->>'bonus_new_chat')::int, bonus_new_chat),
    bonus_invited          = coalesce((p->>'bonus_invited')::int, bonus_invited),
    bonus_first_room       = coalesce((p->>'bonus_first_room')::int, bonus_first_room),
    bonus_referral         = coalesce((p->>'bonus_referral')::int, bonus_referral),
    bonus_online_5min      = coalesce((p->>'bonus_online_5min')::int, bonus_online_5min),
    bonus_online_30min     = coalesce((p->>'bonus_online_30min')::int, bonus_online_30min),
    bonus_online_60min     = coalesce((p->>'bonus_online_60min')::int, bonus_online_60min),
    bonus_online_120min    = coalesce((p->>'bonus_online_120min')::int, bonus_online_120min),
    bonus_price_multiplier = coalesce((p->>'bonus_price_multiplier')::int, bonus_price_multiplier),
    -- Tarif call BARU
    call_audio_cost_per_min = coalesce((p->>'call_audio_cost_per_min')::int, call_audio_cost_per_min),
    call_video_cost_per_min = coalesce((p->>'call_video_cost_per_min')::int, call_video_cost_per_min),
    call_free_minutes_daily = coalesce((p->>'call_free_minutes_daily')::int, call_free_minutes_daily),
    call_cut_pct            = coalesce((p->>'call_cut_pct')::int, call_cut_pct),
    -- Fitur berbayar lain
    filter_gender_cost      = coalesce((p->>'filter_gender_cost')::int, filter_gender_cost),
    nearby_cost             = coalesce((p->>'nearby_cost')::int, nearby_cost),
    -- Room
    room_create_paid        = coalesce((p->>'room_create_paid')::int, room_create_paid),
    room_create_pw_paid     = coalesce((p->>'room_create_pw_paid')::int, room_create_pw_paid),
    room_join_paid          = coalesce((p->>'room_join_paid')::int, room_join_paid),
    room_extend_paid        = coalesce((p->>'room_extend_paid')::int, room_extend_paid),
    room_reads_daily_limit  = coalesce((p->>'room_reads_daily_limit')::int, room_reads_daily_limit),
    new_chats_daily_limit   = coalesce((p->>'new_chats_daily_limit')::int, new_chats_daily_limit),
    subscribe_cut_pct       = coalesce((p->>'subscribe_cut_pct')::int, subscribe_cut_pct),
    subscription_duration_days = coalesce((p->>'subscription_duration_days')::int, subscription_duration_days),
    -- Biaya chat
    cost_chat_text          = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image         = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once          = coalesce((p->>'cost_view_once')::int, cost_view_once),
    -- Share / reengage
    share_url               = coalesce(p->>'share_url', share_url),
    share_click_reward      = coalesce((p->>'share_click_reward')::int, share_click_reward),
    share_click_cap_daily   = coalesce((p->>'share_click_cap_daily')::int, share_click_cap_daily),
    reengage_enabled        = coalesce((p->>'reengage_enabled')::boolean, reengage_enabled),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_update_point_settings(jsonb) from public, anon;
grant execute on function public.admin_update_point_settings(jsonb) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- Publish fitur (tombol di panel admin). Set flag global per fitur.
-- ──────────────────────────────────────────────
create or replace function public.admin_set_feature_flag(
  p_feature text, p_published boolean
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_feature is null or length(trim(p_feature)) = 0 then
    raise exception 'Invalid feature';
  end if;
  update app_settings
    set feature_flags = jsonb_set(
          coalesce(feature_flags, '{}'::jsonb),
          array[p_feature],
          jsonb_build_object('published', coalesce(p_published, false)),
          true
        ),
        updated_at = now()
    where id = 'global';
  return (select feature_flags from app_settings where id = 'global');
end; $$;
revoke execute on function public.admin_set_feature_flag(text, boolean) from public, anon;
grant execute on function public.admin_set_feature_flag(text, boolean) to authenticated, service_role;

-- Baca feature flags (untuk UI admin & gate client).
create or replace function public.get_feature_flags()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return (select coalesce(feature_flags, '{}'::jsonb) from app_settings where id = 'global');
end; $$;
revoke execute on function public.get_feature_flags() from public, anon;
grant execute on function public.get_feature_flags() to authenticated, service_role;
