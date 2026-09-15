-- ============================================
-- ChatYuk: SECURITY HARDENING (audit 2026-09-15)
-- ============================================
-- Temuan audit end-to-end (terverifikasi di DB live):
--   1. ledger_credit/ledger_spend bisa di-EXECUTE anon → cetak/kuras koin.
--   2. app_settings.app_shared_secret terbaca anon (gate send-push/migrate).
--   3. profiles bocor anon: email, ip_address, fcm_token, lat, lon.
--   4. admin_dummy_uids/admin_excluded_uids/call_push/social_push anon.
--   5. list_my_groups(p_uid) tanpa cek auth.uid() → IDOR grup privat.
--   6. wallet_balances (view) tanpa RLS → bocor saldo semua user.
--
-- Prinsip: revoke seketat mungkin, JANGAN ubah semantik fitur. Client sudah
-- disesuaikan (select kolom eksplisit) pada commit yang sama.
-- Idempoten: aman dijalankan ulang.
-- ============================================

-- ── 1. ledger_credit / ledger_spend: larang anon & public ──
revoke execute on function public.ledger_credit(uuid, text, text, integer, text, jsonb) from public, anon;
revoke execute on function public.ledger_spend(uuid, text, integer, text) from public, anon;

-- ── 2. app_settings.app_shared_secret: cabut dari anon/auth ──
-- Ada GRANT SELECT level TABEL → revoke kolom saja tidak cukup. Pola:
-- revoke SELECT tabel, lalu grant SELECT kolom AMAN (tanpa secret).
revoke select on table public.app_settings from anon, authenticated;
grant select (
  id, screenshot_enabled, watermark_enabled, points_enabled, invisible_enabled,
  invisible_admin_uid, gift_cut_pct, withdraw_rate_idr, withdraw_min_coins,
  withdraw_min_account_age_hours, withdraw_max_per_day, withdraw_min_interval_hours,
  coin_tx_max_per_hour, photo_upload_reward, photo_unlock_once, photo_unlock_perm,
  photo_unlock_owner_pct, bonus_registered, bonus_rated, bonus_shared, bonus_profile,
  bonus_first_photo, bonus_room_read, bonus_new_chat, cost_chat_text, cost_chat_image,
  cost_view_once, share_url, share_click_reward, share_click_cap_daily, bonus_online_5min,
  bonus_online_30min, bonus_online_60min, bonus_online_120min, bonus_invited,
  bonus_first_room, bonus_referral, bonus_price_multiplier, room_create_paid,
  room_create_pw_paid, room_join_paid, room_extend_paid, room_reads_daily_limit,
  new_chats_daily_limit, subscribe_cut_pct, subscription_duration_days, cost_post_boost,
  post_boost_hours, posts_daily_limit, bonus_first_friend, require_registration,
  call_all_enabled, room_media_backend, reengage_enabled, excluded_devices,
  ai_global_enabled, ai_max_replies_per_hour, ai_min_interval_sec, ai_guard_enabled,
  call_anon_enabled, excluded_uids, app_font_family, updated_at
) on public.app_settings to anon, authenticated;

-- ── 3. profiles: cabut 5 kolom sensitif (email/IP/lokasi/fcm) ──
-- Pola sama: tabel-level SELECT membuat revoke kolom tidak berlaku.
revoke select on table public.profiles from anon, authenticated;
grant select (
  id, nickname, gender, age, country, city, status, avatar, login_at, created_at,
  last_seen, is_registered, hashtags, points, one_time_actions, room_reads_today,
  new_chats_today, login_streak, last_login_date, loc_source, loc_updated_at,
  share_location, referred_by, followers_count, following_count, subscriber_count,
  subscription_price, friends_count, last_online_notified_at, bonus_balance,
  topup_balance, earned_balance, last_reengage_at
) on public.profiles to anon, authenticated;

-- ── 4. Fungsi internal: larang anon ──
revoke execute on function public.admin_dummy_uids() from public, anon;
revoke execute on function public.admin_excluded_uids() from public, anon;
-- call_push punya 2 overload (p_avatar ada/tidak) — revoke keduanya.
revoke execute on function public.call_push(uuid, uuid, uuid, text, text) from public, anon;
revoke execute on function public.call_push(uuid, uuid, uuid, text, text, text) from public, anon;
revoke execute on function public.social_push(uuid, text, text, jsonb) from public, anon;

-- ── 5. list_my_groups: guard anti-IDOR (p_uid wajib = caller) ──
-- Isi selain guard dipertahankan PERSIS dari definisi live (returns jsonb).
create or replace function public.list_my_groups(p_uid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  -- Cegah enumerasi grup privat user lain: p_uid harus milik pemanggil
  -- (service_role = jalur internal/admin, diizinkan).
  if p_uid <> auth.uid() and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
    from public.rooms r
    where r.is_private = true
      and exists (
        select 1 from public.room_members m
        where m.room_id = r.id and m.user_id = p_uid
      )
  );
end;
$function$;
revoke execute on function public.list_my_groups(uuid) from public, anon;
grant execute on function public.list_my_groups(uuid) to authenticated, service_role;

-- ── 6. wallet_balances (view): pastikan anon tidak bisa baca ──
do $do$
begin
  if exists (select 1 from pg_views where schemaname='public' and viewname='wallet_balances') then
    revoke all on public.wallet_balances from anon;
    -- security_invoker: hormati RLS coin_ledger milik pemanggil (bila ada).
    begin
      execute 'alter view public.wallet_balances set (security_invoker = true)';
    exception when others then null; end;
  end if;
end
$do$;
