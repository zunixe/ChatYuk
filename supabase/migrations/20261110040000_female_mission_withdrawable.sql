-- menyentuh: claim_mission_reward
-- 2026-11-10: hadiah misi PEREMPUAN bisa ditarik lagi (bucket earned, ikut
-- masa tahan withdraw) — TAPI hanya 1 akun per device & per IP:
--   * device: install_id "dimiliki" akun pertama yang menerima hadiah earned
--     di device itu; akun lain (anonim juga) di device itu → bonus.
--   * IP (server, dari header request): akun lain sudah menerima hadiah
--     earned dari IP yang sama < 24 jam → bonus (24 jam saja karena CGNAT).
--   * tanpa baris user_devices → bonus.
-- Laki-laki tetap selalu bonus.

create table if not exists public.mission_payout_devices (
  install_id text primary key,
  user_id    uuid not null,
  claimed_at timestamptz not null default now()
);
alter table public.mission_payout_devices enable row level security;
revoke all on public.mission_payout_devices from anon, authenticated; -- SAFE: tabel baru, hanya dibaca claim_mission_reward (definer)

create index if not exists coin_ledger_mission_earned_ip_idx
  on public.coin_ledger ((metadata->>'ip'), created_at)
  where type = 'mission_reward' and bucket = 'earned';

-- IP klien asli dari header PostgREST (bukan kiriman HP). Hanya IP pemanggil
-- sendiri → aman dipanggil klien (dipakai verifikasi).
create or replace function public._request_ip()
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  h jsonb;
  v text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    return null;
  end;
  if h is null then
    return null;
  end if;
  v := coalesce(h->>'cf-connecting-ip',
                split_part(h->>'x-forwarded-for', ',', 1),
                h->>'x-real-ip');
  return nullif(trim(v), '');
end;
$function$;

-- null = boleh earned; selain itu alasan ditolak.
create or replace function public._mission_payout_eligible(p_uid uuid, p_ip text)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not exists (select 1 from public.user_devices
                  where user_id = p_uid and install_id <> 'unknown') then
    return 'no_device';
  end if;
  if exists (select 1 from public.user_devices d
               join public.mission_payout_devices o on o.install_id = d.install_id
              where d.user_id = p_uid and o.user_id <> p_uid) then
    return 'shared_device';
  end if;
  if p_ip is not null and exists (
       select 1 from public.coin_ledger l
        where l.type = 'mission_reward' and l.bucket = 'earned'
          and l.metadata->>'ip' = p_ip
          and l.created_at > now() - interval '24 hours'
          and l.user_id <> p_uid) then
    return 'shared_ip';
  end if;
  return null;
end;
$function$;
revoke execute on function public._mission_payout_eligible(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.claim_mission_reward(p_user_id uuid, p_mission_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission record;
    v_user_mission record;
    v_period date;
    v_new_points int;
    v_claimed_id bigint;
    v_earned_bal bigint;
    v_is_coins_mission boolean := false;
    v_completed boolean;
    v_gender text;
    v_reward_bucket text;
    v_reason text;
    v_ip text;
BEGIN
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    IF (SELECT points_enabled FROM app_settings WHERE id = 'global') IS FALSE THEN
        RETURN jsonb_build_object('error', 'POINTS_DISABLED');
    END IF;

    SELECT * INTO v_mission
    FROM public.missions
    WHERE mission_key = p_mission_key;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    -- 2026-11-02: tegakkan gender misi di SERVER juga. Sebelumnya misi
    -- female-only (nyonya_1000) difilter hanya di get_user_missions, jadi
    -- male bisa mengklaimnya lewat RPC langsung.
    SELECT gender INTO v_gender FROM public.profiles WHERE id = p_user_id;
    IF v_mission.gender IS NOT NULL
       AND v_mission.gender <> 'all'
       AND COALESCE(v_gender, 'all') <> v_mission.gender THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

    -- Bucket reward: female → earned (withdrawable); selain female → bonus
    -- (tidak bisa dicairkan, tidak bisa ditransfer). Lihat 20261101190000.
    -- 2026-11-09: reward misi SELALU bonus (tidak bisa dicairkan) untuk
    -- semua gender — dulu female → earned = koin gratis bisa jadi uang
    -- lewat multi-akun.
    -- 2026-11-10: female boleh `earned` (bisa ditarik) bila device & IP
    -- tidak dipakai akun lain — lihat _mission_payout_eligible.
    v_reward_bucket := 'bonus';
    v_ip := public._request_ip();

    v_is_coins_mission := (v_mission.target_unit = 'coins');

    IF v_is_coins_mission THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_earned_bal
          FROM public.coin_ledger
         WHERE user_id = p_user_id AND bucket = 'earned';

        v_completed := (v_earned_bal >= v_mission.target_value);
        IF NOT v_completed THEN
            RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
        END IF;

        INSERT INTO public.user_missions
            (user_id, mission_id, progress, is_completed, completed_at, period_date)
        VALUES (
            p_user_id,
            v_mission.id,
            LEAST(v_earned_bal, v_mission.target_value)::int,
            true,
            now(),
            v_period
        )
        ON CONFLICT (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date))
        DO UPDATE SET
            progress = LEAST(v_earned_bal, v_mission.target_value)::int,
            is_completed = true,
            completed_at = COALESCE(user_missions.completed_at, now());
    ELSE
        SELECT * INTO v_user_mission
        FROM public.user_missions
        WHERE user_id = p_user_id
          AND mission_id = v_mission.id
          AND COALESCE(period_date, '1970-01-01'::date) = COALESCE(v_period, '1970-01-01'::date)
          FOR UPDATE;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('error', 'MISSION_NOT_STARTED');
        END IF;

        IF NOT v_user_mission.is_completed THEN
            RETURN jsonb_build_object('error', 'MISSION_NOT_COMPLETED');
        END IF;

        IF v_user_mission.claimed THEN
            RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
        END IF;
    END IF;

    UPDATE public.user_missions
    SET claimed = true, claimed_at = now()
    WHERE user_id = p_user_id
      AND mission_id = v_mission.id
      AND COALESCE(period_date, '1970-01-01'::date) = COALESCE(v_period, '1970-01-01'::date)
      AND claimed = false
    RETURNING id INTO v_claimed_id;

    IF v_claimed_id IS NULL THEN
        RETURN jsonb_build_object('error', 'ALREADY_CLAIMED');
    END IF;

    IF v_gender = 'female' THEN
        -- Serialisasi klaim earned — cegah 2 akun 1 device klaim bersamaan.
        PERFORM pg_advisory_xact_lock(hashtext('mission_payout'));
        v_reason := public._mission_payout_eligible(p_user_id, v_ip);
        IF v_reason IS NULL THEN
            v_reward_bucket := 'earned';
            INSERT INTO public.mission_payout_devices (install_id, user_id)
            SELECT DISTINCT d.install_id, p_user_id
              FROM public.user_devices d
             WHERE d.user_id = p_user_id AND d.install_id <> 'unknown'
            ON CONFLICT (install_id) DO NOTHING;
        END IF;
    END IF;

    INSERT INTO public.coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
    VALUES (p_user_id, v_reward_bucket, 'mission_reward', v_mission.reward_coins, p_mission_key,
            jsonb_strip_nulls(jsonb_build_object('ip', v_ip, 'reason', v_reason)));

    SELECT points INTO v_new_points
    FROM public.profiles
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'coins', v_mission.reward_coins,
        'bucket', v_reward_bucket,
        'reason', v_reason,
        'total_points', v_new_points
    );
END;
$function$;
