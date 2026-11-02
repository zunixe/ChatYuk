-- ══════════════════════════════════════════════════════════════════════
-- Fix `admin_update_point_settings` + dukung setting withdraw
--
-- BUG KRITIS (pre-existing): fungsi ini merujuk 18 kolom yang SUDAH DIHAPUS
-- dari `app_settings` (faucet bonus lama, room_reads_daily_limit,
-- new_chats_daily_limit, share_click_*) → SETIAP pemanggilan gagal
-- `42703: column ... does not exist`. Akibatnya admin TIDAK BISA menyimpan
-- pengaturan poin sama sekali.
--
-- Perbaikan: buang semua rujukan kolom mati, pertahankan yang masih ada,
-- dan tambahkan setting withdraw + batas call gratis female.
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_update_point_settings(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    -- Foto berbayar
    photo_upload_reward    = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once      = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm      = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct = coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    -- Pengali harga tier bonus (koin gratis = 1/multiplier dari koin beli)
    bonus_price_multiplier = coalesce((p->>'bonus_price_multiplier')::int, bonus_price_multiplier),
    -- Tarif call
    call_audio_cost_per_min = coalesce((p->>'call_audio_cost_per_min')::int, call_audio_cost_per_min),
    call_video_cost_per_min = coalesce((p->>'call_video_cost_per_min')::int, call_video_cost_per_min),
    call_cut_pct            = coalesce((p->>'call_cut_pct')::int, call_cut_pct),
    -- Fitur berbayar lain
    filter_gender_cost      = coalesce((p->>'filter_gender_cost')::int, filter_gender_cost),
    nearby_cost             = coalesce((p->>'nearby_cost')::int, nearby_cost),
    -- Room berbayar
    room_create_paid        = coalesce((p->>'room_create_paid')::int, room_create_paid),
    room_create_pw_paid     = coalesce((p->>'room_create_pw_paid')::int, room_create_pw_paid),
    room_join_paid          = coalesce((p->>'room_join_paid')::int, room_join_paid),
    room_extend_paid        = coalesce((p->>'room_extend_paid')::int, room_extend_paid),
    -- Gift & subscribe
    subscribe_cut_pct       = coalesce((p->>'subscribe_cut_pct')::int, subscribe_cut_pct),
    subscription_duration_days = coalesce((p->>'subscription_duration_days')::int, subscription_duration_days),
    gift_cut_pct            = coalesce((p->>'gift_cut_pct')::int, gift_cut_pct),
    -- Biaya chat
    cost_chat_text          = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image         = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once          = coalesce((p->>'cost_view_once')::int, cost_view_once),
    -- Share / reengage
    share_url               = coalesce(p->>'share_url', share_url),
    reengage_enabled        = coalesce((p->>'reengage_enabled')::boolean, reengage_enabled),
    -- Welcome bonus user baru (anti-farming per install/IP)
    welcome_anon_coins      = coalesce((p->>'welcome_anon_coins')::int, welcome_anon_coins),
    welcome_register_coins  = coalesce((p->>'welcome_register_coins')::int, welcome_register_coins),
    welcome_max_claims_per_ip_day = coalesce((p->>'welcome_max_claims_per_ip_day')::int, welcome_max_claims_per_ip_day),
    -- ── Withdraw (tarik saldo `earned` ke DANA) ──
    withdraw_rate_idr       = coalesce((p->>'withdraw_rate_idr')::int, withdraw_rate_idr),
    withdraw_min_coins      = coalesce((p->>'withdraw_min_coins')::int, withdraw_min_coins),
    withdraw_fee_pct        = coalesce((p->>'withdraw_fee_pct')::int, withdraw_fee_pct),
    withdraw_fee_min_idr    = coalesce((p->>'withdraw_fee_min_idr')::int, withdraw_fee_min_idr),
    withdraw_max_per_day    = coalesce((p->>'withdraw_max_per_day')::int, withdraw_max_per_day),
    withdraw_min_interval_hours = coalesce((p->>'withdraw_min_interval_hours')::int, withdraw_min_interval_hours),
    withdraw_min_account_age_hours = coalesce((p->>'withdraw_min_account_age_hours')::int, withdraw_min_account_age_hours),
    -- ── Batas call gratis female → male (menit / hari) ──
    female_free_call_min_per_day = coalesce((p->>'female_free_call_min_per_day')::int, female_free_call_min_per_day),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $function$;

REVOKE EXECUTE ON FUNCTION public.admin_update_point_settings(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_point_settings(jsonb) TO authenticated, service_role;
