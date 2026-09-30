-- ============================================================
-- ChatYuk — Selaraskan Pengaturan Poin admin dengan sistem YukCoin
--
-- Konteks: ekonomi sudah jadi YukCoin (lihat 20261001000000_coin_engine_config,
-- 20261001010000_disable_free_points, 20261003000000_coin_call_no_free).
-- Faucet/bonus gratis kini no-op, kuota gratis call dihapus, dan fitur
-- berbayar diatur lewat kolom tarif (call/filter/nearby/room/photo/gift/
-- subscribe) + config YukCoin v2 + welcome bonus.
--
-- BUG yang diperbaiki (KRITIS):
--   admin_update_point_settings (versi 20261001020000) masih menulis kolom
--   `call_free_minutes_daily` yang DROPPED di 20261003000000 →
--   SETIAP Simpan Pengaturan Poin dari panel admin GAGAL (SQLSTATE 42703
--   "column does not exist"). Migrasi ini menghapus referensi tsb.
--
-- Isi migrasi:
--   1. Rewrite admin_update_point_settings:
--      - buang call_free_minutes_daily (kolom sudah tak ada)
--      - buang field faucet mati (bonus_* lama, room_reads_daily_limit,
--        new_chats_daily_limit, share_click_reward, share_click_cap_daily)
--      - TAMBAH: welcome bonus (welcome_anon_coins, welcome_register_coins,
--        welcome_max_claims_per_ip_day), YukCoin v2 (yukcoin_v2_enabled,
--        cost_undo_message, cost_edit_message, cost_extra_photo_slot,
--        cost_ghost_mode_daily), gift_cut_pct.
--   2. Rewrite points_quests: tak lagi membaca kolom bonus faucet yang akan
--      di-drop (daily quest lama dikosongkan — rewardnya sudah no-op).
--   3. DROP 19 kolom faucet mati di app_settings (semua sudah no-op & tak
--      dibaca fungsi lain kecuali 2 fungsi di atas yang ikut ditulis ulang).
--
-- bonus_price_multiplier TIDAK di-drop (masih dipakai room_pricing,
-- send_gift, unlock_photo — dual pricing bonus).
--
-- admin_update_point_settings & points_quests BUKAN fungsi FROZEN.
-- Idempotent (create or replace / drop column if exists).
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Rewrite admin_update_point_settings — selaras kolom app_settings LIVE
-- ──────────────────────────────────────────────
create or replace function public.admin_update_point_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    -- Call (per menit) + split penerima
    call_audio_cost_per_min = coalesce((p->>'call_audio_cost_per_min')::int, call_audio_cost_per_min),
    call_video_cost_per_min = coalesce((p->>'call_video_cost_per_min')::int, call_video_cost_per_min),
    call_cut_pct            = coalesce((p->>'call_cut_pct')::int, call_cut_pct),
    -- Filter gender & orang sekitar (per hari)
    filter_gender_cost      = coalesce((p->>'filter_gender_cost')::int, filter_gender_cost),
    nearby_cost             = coalesce((p->>'nearby_cost')::int, nearby_cost),
    -- YukCoin v2 (fitur koin generik)
    yukcoin_v2_enabled      = coalesce((p->>'yukcoin_v2_enabled')::boolean, yukcoin_v2_enabled),
    cost_undo_message       = coalesce((p->>'cost_undo_message')::int, cost_undo_message),
    cost_edit_message       = coalesce((p->>'cost_edit_message')::int, cost_edit_message),
    cost_extra_photo_slot   = coalesce((p->>'cost_extra_photo_slot')::int, cost_extra_photo_slot),
    cost_ghost_mode_daily   = coalesce((p->>'cost_ghost_mode_daily')::int, cost_ghost_mode_daily),
    -- Foto
    photo_upload_reward     = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once       = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm       = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct  = coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    -- Biaya chat
    cost_chat_text          = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image         = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once          = coalesce((p->>'cost_view_once')::int, cost_view_once),
    -- Room berbayar (dual pricing memakai bonus_price_multiplier)
    room_create_paid        = coalesce((p->>'room_create_paid')::int, room_create_paid),
    room_create_pw_paid     = coalesce((p->>'room_create_pw_paid')::int, room_create_pw_paid),
    room_join_paid          = coalesce((p->>'room_join_paid')::int, room_join_paid),
    room_extend_paid        = coalesce((p->>'room_extend_paid')::int, room_extend_paid),
    bonus_price_multiplier  = coalesce((p->>'bonus_price_multiplier')::int, bonus_price_multiplier),
    -- Gift & subscribe
    gift_cut_pct            = coalesce((p->>'gift_cut_pct')::int, gift_cut_pct),
    subscribe_cut_pct       = coalesce((p->>'subscribe_cut_pct')::int, subscribe_cut_pct),
    subscription_duration_days = coalesce((p->>'subscription_duration_days')::int, subscription_duration_days),
    -- Welcome bonus (anti-farming per install/IP)
    welcome_anon_coins              = coalesce((p->>'welcome_anon_coins')::int, welcome_anon_coins),
    welcome_register_coins          = coalesce((p->>'welcome_register_coins')::int, welcome_register_coins),
    welcome_max_claims_per_ip_day   = coalesce((p->>'welcome_max_claims_per_ip_day')::int, welcome_max_claims_per_ip_day),
    -- Share link + reengage
    share_url               = coalesce(p->>'share_url', share_url),
    reengage_enabled        = coalesce((p->>'reengage_enabled')::boolean, reengage_enabled),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_update_point_settings(jsonb) from public, anon;
grant execute on function public.admin_update_point_settings(jsonb) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 2. Rewrite points_quests agar tak membaca kolom faucet yang di-drop.
--    Reward faucet sudah no-op sejak 20261001010000 (bonus = 0). Daily
--    quest lama (room_read/new_chat/online_*) dikosongkan; weekly/oneTime
--    tetap dikembalikan sebagai struktur (klien sudah menyembunyikannya
--    saat faucet mati). Saldo = total ledger (sumber benar).
-- ──────────────────────────────────────────────
create or replace function public.points_quests(tz_offset_minutes integer default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  p record;
  wallet_total int;
begin
  select points, room_reads_today, new_chats_today, one_time_actions,
         last_login_date, login_streak
    into p
    from profiles where id = auth.uid();

  select coalesce(sum(amount), 0) into wallet_total
    from coin_ledger where user_id = auth.uid();

  return jsonb_build_object(
    'points', wallet_total,
    'streak', coalesce(p.login_streak, 0),
    'daily', '[]'::jsonb,
    'weekly', '[]'::jsonb,
    'oneTime', '[]'::jsonb
  );
end; $$;
revoke execute on function public.points_quests(int) from public, anon;
grant execute on function public.points_quests(int) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 3. DROP kolom faucet mati (no-op, tak lagi dibaca fungsi lain).
--    Semua reward faucet dimatikan di 20261001010000_disable_free_points;
--    admin_update_point_settings & points_quests sudah ditulis ulang di atas.
-- ──────────────────────────────────────────────
alter table public.app_settings
  drop column if exists bonus_registered,     -- SAFE: faucet mati (20261001010000); hanya dibaca 2 fn yang di-rewrite di atas
  drop column if exists bonus_rated,          -- SAFE: faucet mati; tak ada pembaca tersisa
  drop column if exists bonus_shared,         -- SAFE: faucet mati; share reward dihapus
  drop column if exists bonus_profile,        -- SAFE: faucet mati
  drop column if exists bonus_first_photo,    -- SAFE: faucet mati
  drop column if exists bonus_room_read,      -- SAFE: faucet mati (room_read_bonus no-op)
  drop column if exists bonus_new_chat,       -- SAFE: faucet mati (new_chat_bonus no-op)
  drop column if exists bonus_invited,        -- SAFE: faucet mati
  drop column if exists bonus_first_room,     -- SAFE: faucet mati
  drop column if exists bonus_referral,       -- SAFE: faucet mati (claim_referral_reward no-op)
  drop column if exists bonus_online_5min,    -- SAFE: faucet mati (bonus online dihapus)
  drop column if exists bonus_online_30min,   -- SAFE: faucet mati
  drop column if exists bonus_online_60min,   -- SAFE: faucet mati
  drop column if exists bonus_online_120min,  -- SAFE: faucet mati
  drop column if exists room_reads_daily_limit, -- SAFE: faucet mati (hanya dipakai points_quests lama)
  drop column if exists new_chats_daily_limit,  -- SAFE: faucet mati (hanya dipakai points_quests lama)
  drop column if exists share_click_reward,     -- SAFE: share-click reward dihapus (award_share_click no-op)
  drop column if exists share_click_cap_daily,  -- SAFE: share-click reward dihapus
  drop column if exists bonus_first_friend;     -- SAFE: faucet mati (one_time_bonus no-op); tak ada fn yang membacanya
