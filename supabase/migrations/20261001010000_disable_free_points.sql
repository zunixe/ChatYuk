-- ============================================================
-- ChatYuk — HAPUS SEMUA POIN GRATIS (faucet) — Okt 2026
--
-- Konteks: lihat 20261001000000_coin_engine_config.sql. Coin kini HANYA
-- dari topup Google Play Billing (+ 30% income call). Semua jalur poin
-- gratis dimatikan menjadi no-op (mengembalikan saldo apa adanya, tanpa
-- menambah coin & tanpa menandai one_time_actions).
--
-- Fungsi FROZEN yang disentuh (WAJIB header '-- menyentuh:'):
--   daily_login_bonus, one_time_bonus, register_bonus (via one_time),
--   room_read_bonus, new_chat_bonus, claim_weekly_quest
-- plus trigger signup (profiles_ledger_signup_trg) dimatikan.
--
-- CATATAN: reward_photo_slot & claim_referral_reward BUKAN fungsi frozen di
-- file ini (reward_photo_slot tidak ada di frozen_functions.txt;
-- claim_referral_reward juga tidak). Tetap di-no-op di sini.
--
-- Setelah apply: WAJIB jalankan scripts/snapshot_functions.sh + review diff.
-- Idempotent (create or replace).
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. daily_login_bonus → no-op (streak dihapus)
-- ──────────────────────────────────────────────
-- menyentuh: daily_login_bonus
create or replace function public.daily_login_bonus()
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur_points int;
begin
  select points into cur_points from profiles where id = auth.uid();
  return jsonb_build_object('points', coalesce(cur_points, 0), 'streak', 0, 'bonus', 0);
end; $$;
revoke execute on function public.daily_login_bonus() from public, anon;
grant execute on function public.daily_login_bonus() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 2. streak_bonus_amount → 0 (jaga kompat kalau masih dipanggil)
-- ──────────────────────────────────────────────
create or replace function public.streak_bonus_amount(streak int)
returns int language sql immutable as $$ select 0; $$;

-- ──────────────────────────────────────────────
-- 3. one_time_bonus → no-op (whitelist tetap divalidasi agar caller lama
--    tidak error; tapi tidak memberi bonus & tidak menandai action).
-- ──────────────────────────────────────────────
-- menyentuh: one_time_bonus
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  -- No-op: bonus gratis dihapus. Kembalikan saldo apa adanya.
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 4. register_bonus → no-op
-- ──────────────────────────────────────────────
create or replace function public.register_bonus()
returns int language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.register_bonus() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 5. room_read_bonus → no-op
-- ──────────────────────────────────────────────
-- menyentuh: room_read_bonus
create or replace function public.room_read_bonus()
returns int language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.room_read_bonus() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 6. new_chat_bonus → no-op
-- ──────────────────────────────────────────────
-- menyentuh: new_chat_bonus
create or replace function public.new_chat_bonus(other_uid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.new_chat_bonus(uuid) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 7. reward_photo_slot → no-op
-- ──────────────────────────────────────────────
create or replace function public.reward_photo_slot(p_slot_index int)
returns int language plpgsql security definer set search_path = public as $$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.reward_photo_slot(int) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 8. claim_referral_reward → no-op (referral install reward dihapus)
-- ──────────────────────────────────────────────
create or replace function public.claim_referral_reward()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('rewarded', false, 'reason', 'disabled');
end; $$;
revoke execute on function public.claim_referral_reward() from public, anon;
grant execute on function public.claim_referral_reward() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 9. claim_weekly_quest → no-op (misi mingguan reward dihapus)
-- ──────────────────────────────────────────────
-- menyentuh: claim_weekly_quest
create or replace function public.claim_weekly_quest(quest_key text, tz_offset_minutes int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('points', public.yukcoin_total(auth.uid()), 'claimed', false);
end; $$;
revoke execute on function public.claim_weekly_quest(text, int) from public, anon;
grant execute on function public.claim_weekly_quest(text, int) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 10. award_share_click → no-op (share reward sudah mati)
-- ──────────────────────────────────────────────
create or replace function public.award_share_click(p_sharer uuid, p_ip text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('ok', true, 'rewarded', false);
end; $$;
revoke execute on function public.award_share_click(uuid, text) from public, anon;
grant execute on function public.award_share_click(uuid, text) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 11. Signup bonus trigger → DIMATIKAN
--     Saldo awal user baru = 0 (default profiles.points = 0).
-- ──────────────────────────────────────────────
drop trigger if exists profiles_ledger_signup_trg on public.profiles; -- SAFE: nonaktifkan signup bonus; saldo awal 0 diatur via default kolom points (lihat 20261001020000)

-- ──────────────────────────────────────────────
-- 12. profiles.points default → 0 (tidak ada saldo awal gratis)
-- ──────────────────────────────────────────────
alter table public.profiles alter column points set default 0;
