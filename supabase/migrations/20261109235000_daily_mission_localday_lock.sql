-- ============================================================
-- 235000 — Misi harian: batas hari mengikuti ZONA WAKTU PENGGUNA
--          + kunci 1.200 koin ditegakkan di server
-- ============================================================
-- menyentuh: daily_login_bonus
--
-- Masalah yang diperbaiki:
--  1. Batas hari TIDAK konsisten: bonus login memakai Asia/Jakarta,
--     sedangkan misi harian memakai CURRENT_DATE (UTC) — sementara klien
--     membaca progres memakai tanggal lokal HP. Di luar WIB (atau sekitar
--     pergantian hari) progres yang tampil beda dengan yang bisa diklaim.
--  2. Kunci "misi harian terbuka setelah 1.200 koin" hanya dikirim sebagai
--     `unlocked_by_total`; klien membaca `is_locked` (tidak pernah dikirim)
--     dan server tidak menolak klaim/progres saat masih terkunci.
--
-- Solusi:
--  * Helper `_local_day(p_tz_offset_minutes)`: tanggal lokal pengguna dari
--    offset zona waktu HP (clamp ±14 jam). Default +420 (Asia/Jakarta) agar
--    klien lama tetap berperilaku sama.
--  * `get_user_missions`, `update_mission_progress`, `claim_mission_reward`,
--    `daily_login_bonus` menerima `p_tz_offset_minutes` opsional.
--  * Output misi harian menyertakan `is_locked` (v_total < 1200) dan misi
--    utama menyertakan `is_locked` dari tabel missions.
--  * Progres & klaim misi harian DITOLAK (`MISSION_LOCKED`) selama total
--    kredit seumur hidup < 1200.
--
-- Kompatibilitas: parameter baru ber-default NULL → panggilan lama (2 arg
-- untuk get_user_missions / 2 arg claim / 3 arg update / 0 arg login) tetap
-- jalan lewat signature baru. Signature lama di-drop agar tidak ambigu.

-- ── Helper tanggal lokal ──────────────────────────────────────────────
create or replace function public._local_day(p_tz_offset_minutes int default null)
returns date
language sql
stable
as $$
  select ((now() at time zone 'UTC')
          + make_interval(mins => least(greatest(coalesce(p_tz_offset_minutes, 420), -840), 840))
         )::date;
$$;

revoke execute on function public._local_day(int) from public, anon;
grant execute on function public._local_day(int) to authenticated, service_role;

-- ── get_user_missions ─────────────────────────────────────────────────
-- SAFE: drop signature lama (uuid, date) — diganti (uuid, date, int) yang
-- kompatibel dengan pemanggil lama (param ke-3 ber-default). Hanya RPC
-- baca; tidak ada objek DB lain yang bergantung.
drop function if exists public.get_user_missions(uuid, date);

create or replace function public.get_user_missions(
    p_user_id uuid,
    p_period_date date default null,
    p_tz_offset_minutes int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
DECLARE
    result jsonb;
    v_period date;
    v_total bigint;
    v_earned_bal bigint;
    v_streak int;
    v_last_login date;
    v_gender text;
    v_locked boolean;
BEGIN
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    -- Tanggal lokal pengguna (offset dari HP). Klien baru mengirim tanggal
    -- lokalnya sendiri; fallback: hitung dari offset / Asia/Jakarta.
    v_period := COALESCE(p_period_date, public._local_day(p_tz_offset_minutes));

    SELECT COALESCE(SUM(amount), 0) INTO v_total
      FROM public.coin_ledger
     WHERE user_id = p_user_id AND amount > 0;

    SELECT COALESCE(SUM(amount), 0) INTO v_earned_bal
      FROM public.coin_ledger
     WHERE user_id = p_user_id AND bucket = 'earned';

    SELECT login_streak, last_login_date, gender
      INTO v_streak, v_last_login, v_gender
      FROM public.profiles
     WHERE id = p_user_id;

    v_locked := (v_total < 1200);

    WITH main_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order, m.is_locked,
               CASE WHEN m.target_unit = 'coins'
                    THEN GREATEST(0, LEAST(v_earned_bal, m.target_value))::int
                    ELSE COALESCE(um.progress, 0) END AS progress,
               CASE WHEN m.target_unit = 'coins'
                    THEN (v_earned_bal >= m.target_value)
                    ELSE COALESCE(um.is_completed, false) END AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date IS NULL
        WHERE NOT m.is_daily
          AND (m.gender = 'all' OR m.gender = COALESCE(v_gender, 'all'))
    ),
    daily_missions AS (
        SELECT m.id, m.mission_key, m.title, m.description,
               m.category, m.target_value, m.target_unit, m.reward_coins,
               m.display_order, m.unlock_condition, m.schedule_start, m.schedule_end,
               v_locked AS is_locked,
               COALESCE(um.progress, 0) AS progress,
               COALESCE(um.is_completed, false) AS is_completed,
               COALESCE(um.claimed, false) AS claimed,
               um.completed_at,
               (NOT v_locked) AS unlocked_by_total
        FROM public.missions m
        LEFT JOIN public.user_missions um
               ON m.id = um.mission_id
              AND um.user_id = p_user_id
              AND um.period_date = v_period
        WHERE m.is_daily
          AND (m.gender = 'all' OR m.gender = COALESCE(v_gender, 'all'))
    )
    SELECT jsonb_build_object(
        'main', (SELECT jsonb_agg(row_to_json(m) ORDER BY m.display_order) FROM main_missions m),
        'daily', (SELECT jsonb_agg(row_to_json(dm) ORDER BY dm.display_order) FROM daily_missions dm),
        'total_coins', v_total,
        'daily_locked', v_locked,
        'period_date', v_period,
        'login_streak', COALESCE(v_streak, 0),
        'last_login_date', v_last_login,
        'gender', v_gender
    ) INTO result;

    RETURN result;
END;
$function$;

revoke execute on function public.get_user_missions(uuid, date, int) from public, anon;
grant execute on function public.get_user_missions(uuid, date, int) to authenticated, service_role;

-- ── update_mission_progress ───────────────────────────────────────────
-- SAFE: drop signature lama (uuid, text, int) → (uuid, text, int, int).
drop function if exists public.update_mission_progress(uuid, text, integer);

create or replace function public.update_mission_progress(
    p_user_id uuid,
    p_mission_key text,
    p_increment integer default 1,
    p_tz_offset_minutes int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
DECLARE
    v_mission record;
    v_period date;
    v_progress int;
    v_completed boolean;
    v_inc int;
    v_last timestamptz;
    v_total bigint;
BEGIN
    if auth.uid() is not null and p_user_id is distinct from auth.uid() then
        return jsonb_build_object('error', 'FORBIDDEN');
    end if;

    -- Clamp 1..120: nilai di luar itu dianggap tidak sah.
    v_inc := coalesce(p_increment, 1);
    if v_inc < 1 then v_inc := 1; end if;
    if v_inc > 120 then v_inc := 120; end if;

    SELECT * INTO v_mission
    FROM public.missions
    WHERE mission_key = p_mission_key;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'MISSION_NOT_FOUND');
    END IF;

    -- Tanggal lokal pengguna — sama dengan yang dipakai klien saat membaca.
    v_period := CASE WHEN v_mission.is_daily
                     THEN public._local_day(p_tz_offset_minutes) ELSE NULL END;

    -- Kunci 1.200 koin: misi harian belum boleh menambah progres.
    IF v_mission.is_daily THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_total
          FROM public.coin_ledger
         WHERE user_id = p_user_id AND amount > 0;
        IF v_total < 1200 THEN
            RETURN jsonb_build_object('error', 'MISSION_LOCKED');
        END IF;
    END IF;

    -- 2026-11-10: panggilan KLIEN dibatasi kecepatan nyata — dulu satu
    -- panggilan p_increment=120 menyelesaikan misi apa pun seketika.
    --  * satuan menit: naik maksimal sebanyak menit yang benar-benar lewat
    --    sejak kenaikan terakhir (min 1);
    --  * satuan lain: maksimal 1, paling cepat tiap 5 detik.
    -- GUC `role` = asal permintaan (fungsi ini definer → current_user owner).
    IF coalesce(current_setting('role', true), 'none') IN ('authenticated', 'anon') THEN
        SELECT last_increment_at INTO v_last
          FROM public.user_missions
         WHERE user_id = p_user_id AND mission_id = v_mission.id
           AND COALESCE(period_date, '1970-01-01'::date)
               = COALESCE(v_period, '1970-01-01'::date);
        IF v_mission.target_unit = 'minutes' THEN
            v_inc := least(v_inc, greatest(1,
                CASE WHEN v_last IS NULL THEN 1
                     ELSE floor(extract(epoch FROM now() - v_last) / 60)::int END));
        ELSE
            IF v_last IS NOT NULL AND v_last > now() - interval '5 seconds' THEN
                RETURN jsonb_build_object('error', 'RATE_LIMITED');
            END IF;
            v_inc := 1;
        END IF;
    END IF;

    INSERT INTO public.user_missions
        (user_id, mission_id, progress, is_completed, completed_at, period_date,
         last_increment_at)
    VALUES (
        p_user_id,
        v_mission.id,
        LEAST(v_inc, v_mission.target_value),
        v_inc >= v_mission.target_value,
        CASE WHEN v_inc >= v_mission.target_value THEN now() END,
        v_period,
        now()
    )
    ON CONFLICT (user_id, mission_id, COALESCE(period_date, '1970-01-01'::date)) DO UPDATE SET
        last_increment_at = now(),
        progress = LEAST(user_missions.progress + v_inc, v_mission.target_value),
        is_completed = (user_missions.progress + v_inc >= v_mission.target_value),
        completed_at = CASE
            WHEN user_missions.progress + v_inc >= v_mission.target_value
                 AND NOT user_missions.is_completed
            THEN now()
            ELSE user_missions.completed_at
        END
    RETURNING progress, is_completed INTO v_progress, v_completed;

    RETURN jsonb_build_object(
        'progress', v_progress,
        'target', v_mission.target_value,
        'completed', v_completed,
        'reward_coins', v_mission.reward_coins
    );
END;
$function$;

revoke execute on function public.update_mission_progress(uuid, text, integer, int) from public, anon;
grant execute on function public.update_mission_progress(uuid, text, integer, int) to authenticated, service_role;

-- ── claim_mission_reward ──────────────────────────────────────────────
-- SAFE: drop signature lama (uuid, text) → (uuid, text, int).
drop function if exists public.claim_mission_reward(uuid, text);

create or replace function public.claim_mission_reward(
    p_user_id uuid,
    p_mission_key text,
    p_tz_offset_minutes int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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
    v_total bigint;
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

    -- Tanggal lokal pengguna — sama dengan periode progres yang ditulis
    -- update_mission_progress (dulu UTC vs klien lokal = beda hari).
    v_period := CASE WHEN v_mission.is_daily
                     THEN public._local_day(p_tz_offset_minutes) ELSE NULL END;

    -- Kunci 1.200 koin: misi harian belum boleh diklaim.
    IF v_mission.is_daily THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_total
          FROM public.coin_ledger
         WHERE user_id = p_user_id AND amount > 0;
        IF v_total < 1200 THEN
            RETURN jsonb_build_object('error', 'MISSION_LOCKED');
        END IF;
    END IF;

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

revoke execute on function public.claim_mission_reward(uuid, text, int) from public, anon;
grant execute on function public.claim_mission_reward(uuid, text, int) to authenticated, service_role;

-- ── daily_login_bonus (FROZEN) ────────────────────────────────────────
-- SAFE: drop signature lama () → (int) agar tidak ambigu (param default).
drop function if exists public.daily_login_bonus();

create or replace function public.daily_login_bonus(
    p_tz_offset_minutes int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  today date;
  last_date date;
  cur_streak int;
  new_streak int;
  bonus int;
  v_gender text;
begin
  -- Tanggal lokal pengguna (offset HP) — bukan lagi hardcode Asia/Jakarta.
  today := public._local_day(p_tz_offset_minutes);

  select last_login_date, login_streak, gender
    into last_date, cur_streak, v_gender
    from profiles where id = auth.uid();

  if v_gender is null then
    return jsonb_build_object('streak', 0, 'bonus', 0, 'total',
      public.yukcoin_total(auth.uid()));
  end if;

  -- Kill-switch ekonomi: points_enabled=false → tanpa kredit.
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('streak', coalesce(cur_streak, 0), 'bonus', 0,
      'total', public.yukcoin_total(auth.uid()));
  end if;

  -- Male only: female tidak pernah dapat tetesan koin gratis.
  if v_gender <> 'male' then
    return jsonb_build_object('streak', coalesce(cur_streak, 0), 'bonus', 0,
      'total', public.yukcoin_total(auth.uid()));
  end if;

  -- Sudah klaim hari ini → idempotent, tidak menambah koin.
  if last_date is not null and last_date >= today then
    return jsonb_build_object('streak', coalesce(cur_streak, 0), 'bonus', 0,
      'total', public.yukcoin_total(auth.uid()));
  end if;

  -- Streak: lanjut bila kemarin klaim; siklus ulang setelah hari ke-7.
  if last_date is not null and last_date = today - 1 then
    new_streak := coalesce(cur_streak, 0) + 1;
    if new_streak > 7 then
      new_streak := 1;
    end if;
  else
    new_streak := 1;
  end if;

  bonus := public.streak_bonus_amount(new_streak);

  update profiles set
    login_streak = new_streak,
    last_login_date = today,
    login_at = now(),
    room_reads_today = 0,
    new_chats_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min'
    ]
  where id = auth.uid();

  -- Bucket 'bonus' = non-withdrawable; wallet ikut via wallet_sync_points.
  perform public.ledger_credit(auth.uid(), 'bonus', 'daily_login', bonus,
    'daily_login', jsonb_build_object('streak', new_streak));

  return jsonb_build_object('streak', new_streak, 'bonus', bonus,
    'total', public.yukcoin_total(auth.uid()));
end;
$function$;

revoke execute on function public.daily_login_bonus(int) from public, anon;
grant execute on function public.daily_login_bonus(int) to authenticated, service_role;
