-- ══════════════════════════════════════════════════════════════════════
-- Review ulang ekonomi (2026-11-10) — Fase 1: kontrol yang bisa dilewati.
-- 1. withdraw_accounts & subscriptions: klien hanya SELECT; tulis lewat RPC
--    (save_withdraw_account / request_withdraw / subscribe_creator). Dulu
--    PATCH langsung melewati cooldown nomor DANA & membuat langganan gratis.
-- 2. profiles: subscription_price hanya via set_subscription_price;
--    is_registered dihitung dari akun terverifikasi (auth.users); INSERT
--    profil oleh klien dijaga (saldo 0, created_at now, gender terkunci).
-- 3. Nomor DANA unik antar akun (DANA_IN_USE); request_withdraw menahan
--    (UNDER_REVIEW) penghasilan dari akun yang berbagi device.
-- 4. admin_withdraw_process: approve ditolak bila ada fraud_holds terbuka;
--    reviewed_by = auth.uid() (bukan lewat profiles.email yg bisa ditulis).
-- 5. subscribe_creator(p_expected_price) → PRICE_CHANGED.
-- 6. send_gift: wallet lock. 7. user_fcm_tokens: internal saja.
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. Tabel hanya-baca untuk klien ─────────────────────────────────────
drop policy if exists withdraw_accounts_own on public.withdraw_accounts; -- SAFE: diganti SELECT-only; fitur: withdraw (tulis via RPC definer)
create policy withdraw_accounts_select_own on public.withdraw_accounts for select using (user_id = auth.uid()); -- SAFE: baca akun DANA sendiri; fitur: withdraw
revoke insert, update, delete, truncate on public.withdraw_accounts from anon, authenticated; -- SAFE: klien tak pernah menulis (grep lib/ = 0); tulis via save_withdraw_account/request_withdraw (definer)

drop policy if exists subscriptions_insert_own on public.subscriptions; -- SAFE: insert langganan hanya via subscribe_creator; fitur: langganan kreator
drop policy if exists subscriptions_update_own on public.subscriptions; -- SAFE: update langganan hanya via subscribe_creator; fitur: langganan kreator
revoke insert, update, delete, truncate on public.subscriptions from anon, authenticated; -- SAFE: klien hanya SELECT (timeline_provider); tulis via subscribe_creator (definer)

-- ── 2. Guard kolom profiles ─────────────────────────────────────────────
create or replace function public.profile_is_verified(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from auth.users u
     where u.id = p_uid
       and coalesce(u.is_anonymous, false) = false
       and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null));
$function$;
revoke execute on function public.profile_is_verified(uuid) from public, anon, authenticated;

-- menyentuh: guard_economy_columns
create or replace function public.guard_economy_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_trusted boolean :=
    coalesce(current_setting('chatyuk.economy_ok', true), '') = '1';
begin
  if auth.uid() is null
     or coalesce(auth.role(), '') = 'service_role'
     or v_trusted
     or public.is_chatyuk_admin(auth.uid()) then
    return new;
  end if;
  -- Hanya permintaan dari KLIEN (role sesi PostgREST). Catatan: fungsi ini
  -- SECURITY DEFINER → current_user selalu pemilik; yang menunjukkan asal
  -- permintaan adalah GUC `role`. RPC resmi (set_subscription_price)
  -- menandai dirinya lewat chatyuk.economy_ok (lihat v_trusted).
  if coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.points := 0;
    new.bonus_balance := 0;
    new.topup_balance := 0;
    new.earned_balance := 0;
    new.created_at := now();
    new.subscription_price := 0;
    new.is_registered := coalesce(new.is_registered, false)
                         and public.profile_is_verified(new.id);
    if new.gender is not null then new.gender_locked := true; end if;
    return new;
  end if;

  if new.points is distinct from old.points then new.points := old.points; end if;
  if new.bonus_balance is distinct from old.bonus_balance then
    new.bonus_balance := old.bonus_balance; end if;
  if new.topup_balance is distinct from old.topup_balance then
    new.topup_balance := old.topup_balance; end if;
  if new.earned_balance is distinct from old.earned_balance then
    new.earned_balance := old.earned_balance; end if;
  if new.created_at is distinct from old.created_at then
    new.created_at := old.created_at; end if;
  if new.subscription_price is distinct from old.subscription_price then
    new.subscription_price := old.subscription_price; end if;
  -- Naik ke "terdaftar" hanya bila akun benar-benar terverifikasi.
  if new.is_registered is distinct from old.is_registered
     and new.is_registered is true
     and not public.profile_is_verified(new.id) then
    new.is_registered := old.is_registered;
  end if;
  return new;
end;
$function$;

drop trigger if exists guard_economy_columns_trg on public.profiles;
create trigger guard_economy_columns_trg
  before insert or update of points, bonus_balance, topup_balance, earned_balance,
    created_at, subscription_price, is_registered
  on public.profiles
  for each row execute function public.guard_economy_columns();

-- RPC resmi ganti harga langganan → tandai jalur tepercaya untuk guard.
create or replace function public.set_subscription_price(p_price integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare me uuid := auth.uid(); am_registered boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select is_registered into am_registered from profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;
  if p_price < 0 or p_price > 100000 then raise exception 'Invalid price'; end if;
  perform set_config('chatyuk.economy_ok', '1', true);
  update profiles set subscription_price = p_price where id = me;
  perform set_config('chatyuk.economy_ok', '', true);
  return jsonb_build_object('ok', true, 'price', p_price);
end; $function$;

-- ── 3. Nomor DANA unik ─────────────────────────────────────────────────
-- menyentuh: save_withdraw_account
create or replace function public.save_withdraw_account(p_dana_number text, p_dana_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_num text;
    v_name text;
    v_acc record;
    v_cd_hours int;
    v_free timestamptz;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Normalisasi nomor: buang spasi/strip, wajib 08xx atau 62xx, 10-14 digit.
    v_num := regexp_replace(coalesce(p_dana_number, ''), '[^0-9]', '', 'g');
    IF v_num !~ '^(08|62)[0-9]{8,13}$' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NUMBER');
    END IF;
    -- 62xx → 0xx (format DANA domestik).
    IF v_num LIKE '62%' THEN
        v_num := '0' || substring(v_num from 3);
    END IF;

    v_name := nullif(trim(coalesce(p_dana_name, '')), '');
    IF v_name IS NULL OR length(v_name) < 3 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NAME');
    END IF;

    -- Cooldown ganti nomor (Fase B): nomor BERBEDA dari tersimpan tak
    -- boleh diganti sebelum cooldown berlalu. Nomor sama/nama saja → bebas.
    SELECT coalesce(withdraw_dana_change_cooldown_hours, 168)
      INTO v_cd_hours
      FROM public.app_settings WHERE id = 'global';
    SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
    IF FOUND AND v_acc.dana_number IS DISTINCT FROM v_num
       AND v_acc.updated_at > now() - make_interval(hours => v_cd_hours) THEN
        v_free := v_acc.updated_at + make_interval(hours => v_cd_hours);
        RETURN jsonb_build_object('ok', false,
            'error', 'DANA_CHANGE_COOLDOWN',
            'cooldown_until', v_free,
            'cooldown_hours', v_cd_hours);
    END IF;

    -- 2026-11-10: satu nomor DANA = satu akun (cegah banyak akun "penerima"
    -- mengalir ke satu dompet / akun sendiri).
    IF EXISTS (SELECT 1 FROM public.withdraw_accounts
                WHERE dana_number = v_num AND user_id <> v_uid) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DANA_IN_USE');
    END IF;

    INSERT INTO public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
    VALUES (v_uid, v_num, v_name, now())
    ON CONFLICT (user_id) DO UPDATE SET
        dana_number = excluded.dana_number,
        dana_name = excluded.dana_name,
        updated_at = case
          when withdraw_accounts.dana_number is distinct from excluded.dana_number
            then now()
          else withdraw_accounts.updated_at
        end;

    RETURN jsonb_build_object('ok', true,
        'dana_number', v_num, 'dana_name', v_name);
END;
$function$;

-- menyentuh: request_withdraw
create or replace function public.request_withdraw(p_coins integer, p_dana_number text DEFAULT NULL::text, p_dana_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_uid uuid := auth.uid();
    v_gender text;
    v_total int;
    v_min_coins int;
    v_rate int;
    v_fee_pct int;
    v_fee_min int;
    v_max_day int;
    v_min_interval int;
    v_min_age int;
    v_today_count int;
    v_last_req timestamptz;
    v_created_at timestamptz;
    v_gross int;
    v_fee int;
    v_net int;
    v_num text;
    v_name text;
    v_acc record;
    v_req_id uuid;
    v_require_kyc boolean;
    v_dana_cd_hours int;
    v_dana_free timestamptz;
    v_hold_days int;
    v_max_coins_day int;
    v_held int;
    v_available int;
    v_today_coins int;
    v_day_start timestamptz :=
      (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
         AT TIME ZONE 'Asia/Jakarta');
begin
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('withdraw:' || v_uid::text));

    IF (SELECT points_enabled FROM app_settings WHERE id = 'global') IS FALSE THEN
        RETURN jsonb_build_object('ok', false, 'error', 'POINTS_DISABLED');
    END IF;

    SELECT gender INTO v_gender FROM public.profiles WHERE id = v_uid;
    IF v_gender IS DISTINCT FROM 'female' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'FEMALE_ONLY');
    END IF;

    SELECT coalesce(withdraw_min_coins, 1500),
           coalesce(withdraw_rate_idr, 7),
           coalesce(withdraw_fee_pct, 5),
           coalesce(withdraw_fee_min_idr, 1000),
           coalesce(withdraw_max_per_day, 3),
           coalesce(withdraw_min_interval_hours, 1),
           coalesce(withdraw_min_account_age_hours, 72),
           coalesce(withdraw_require_kyc, true),
           coalesce(withdraw_dana_change_cooldown_hours, 168),
           coalesce(withdraw_hold_days, 7),
           coalesce(withdraw_max_coins_per_day, 50000)
      INTO v_min_coins, v_rate, v_fee_pct, v_fee_min,
           v_max_day, v_min_interval, v_min_age,
           v_require_kyc, v_dana_cd_hours,
           v_hold_days, v_max_coins_day
      FROM public.app_settings WHERE id = 'global';

    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

    -- 2026-11-01 (190000): HANYA bucket `earned` yang bisa ditarik.
    -- Koin `bonus` (gratis) tidak boleh dicairkan jadi uang.
    SELECT coalesce(sum(amount) filter (where bucket = 'earned'), 0) INTO v_total
      FROM public.coin_ledger WHERE user_id = v_uid;

    IF v_total < p_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INSUFFICIENT_BALANCE',
            'balance', v_total);
    END IF;

    -- 2026-11-09: masa tahan — penghasilan v_hold_days hari terakhir belum
    -- bisa dicairkan (jendela refund Google Play / sengketa).
    v_held := public.earned_held(v_uid, v_hold_days);
    v_available := greatest(0, v_total - v_held);
    IF v_available < p_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'HELD_BALANCE',
            'available', v_available, 'held', least(v_held, v_total),
            'hold_days', v_hold_days);
    END IF;

    -- 2026-11-10: akun sendiri — penghasilan 30 hari terakhir mengalir dari
    -- akun yang PERNAH login di device yang sama → tahan untuk ditinjau.
    IF EXISTS (
        SELECT 1 FROM public.platform_revenue pr
         WHERE pr.to_user = v_uid
           AND pr.created_at > now() - interval '30 days'
           AND pr.from_user IN (
               SELECT d2.user_id FROM public.user_devices d1
                 JOIN public.user_devices d2 ON d2.install_id = d1.install_id
                WHERE d1.user_id = v_uid AND d2.user_id <> v_uid)) THEN
        INSERT INTO public.fraud_holds (user_id, reason, ref_id)
        VALUES (v_uid, 'shared_device', NULL)
        ON CONFLICT DO NOTHING;
    END IF;

    -- 2026-11-09: akun ditahan (mis. terkait pembelian Play yang di-refund).
    IF EXISTS (SELECT 1 FROM public.fraud_holds
                WHERE user_id = v_uid AND resolved_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'UNDER_REVIEW');
    END IF;

    SELECT created_at INTO v_created_at FROM public.profiles WHERE id = v_uid;
    IF v_created_at IS NOT NULL
       AND v_created_at > now() - make_interval(hours => v_min_age) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ACCOUNT_TOO_NEW',
            'min_age_hours', v_min_age);
    END IF;

    -- (a) DIPULIHKAN: pengajuan yang DITOLAK tidak lagi menghitung kuota
    -- harian maupun cooldown. Tanpa `status <> 'rejected'`, user yang kalah
    -- satu kali harus menunggu 1 jam dan kehabisan kuota 3/hari padahal
    -- tidak ada uang yang keluar.
    SELECT count(*) INTO v_today_count
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND created_at >= v_day_start
       AND status <> 'rejected';
    IF v_today_count >= v_max_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_LIMIT',
            'max_per_day', v_max_day);
    END IF;

    -- 2026-11-09: batas NOMINAL per hari (selain jumlah request).
    SELECT coalesce(sum(coin_amount), 0) INTO v_today_coins
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND created_at >= v_day_start
       AND status <> 'rejected';
    IF v_today_coins + p_coins > v_max_coins_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_AMOUNT_LIMIT',
            'max_coins_per_day', v_max_coins_day,
            'remaining', greatest(0, v_max_coins_day - v_today_coins));
    END IF;

    -- N8 (2026-11-09): gerbang KYC SEBELUM menyimpan nomor DANA — dulu
    -- request yang ditolak KYC tetap menyimpan nomor & memulai cooldown.
    IF v_require_kyc AND NOT EXISTS (
        SELECT 1 FROM public.kyc_requests
         WHERE user_id = v_uid AND status = 'approved') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'KYC_REQUIRED');
    END IF;

    SELECT max(created_at) INTO v_last_req
      FROM public.withdrawal_requests
     WHERE user_id = v_uid
       AND status <> 'rejected';
    IF v_last_req IS NOT NULL
       AND v_last_req > now() - make_interval(hours => v_min_interval) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'TOO_SOON',
            'min_interval_hours', v_min_interval);
    END IF;

    IF p_dana_number IS NOT NULL AND p_dana_name IS NOT NULL THEN
        v_num := regexp_replace(p_dana_number, '[^0-9]', '', 'g');
        IF v_num !~ '^(08|62)[0-9]{8,13}$' THEN
            RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NUMBER');
        END IF;
        IF v_num LIKE '62%' THEN v_num := '0' || substring(v_num from 3); END IF;
        v_name := nullif(trim(p_dana_name), '');
        IF v_name IS NULL OR length(v_name) < 3 THEN
            RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NAME');
        END IF;

        -- B3: Cooldown ganti nomor — nomor yang BERBEDA dari tersimpan
        -- tak boleh diganti sebelum `withdraw_dana_change_cooldown_hours`
        -- sejak updated_at. Nomor sama / hanya ganti nama → bebas.
        SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
        IF FOUND AND v_acc.dana_number IS DISTINCT FROM v_num
           AND v_acc.updated_at > now() - make_interval(hours => v_dana_cd_hours) THEN
            v_dana_free := v_acc.updated_at + make_interval(hours => v_dana_cd_hours);
            RETURN jsonb_build_object('ok', false,
                'error', 'DANA_CHANGE_COOLDOWN',
                'cooldown_until', v_dana_free,
                'cooldown_hours', v_dana_cd_hours);
        END IF;

        IF EXISTS (SELECT 1 FROM public.withdraw_accounts
                    WHERE dana_number = v_num AND user_id <> v_uid) THEN
            RETURN jsonb_build_object('ok', false, 'error', 'DANA_IN_USE');
        END IF;

        INSERT INTO public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
        VALUES (v_uid, v_num, v_name, now())
        ON CONFLICT (user_id) DO UPDATE SET
            dana_number = excluded.dana_number,
            dana_name = excluded.dana_name,
            updated_at = case
              -- updated_at maju HANYA saat nomor berubah → cooldown diukur
              -- dari ganti nomor terakhir, bukan edit nama.
              when withdraw_accounts.dana_number is distinct from excluded.dana_number
                then now()
              else withdraw_accounts.updated_at
            end;
    ELSE
        SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'error', 'NO_ACCOUNT');
        END IF;
        v_num := v_acc.dana_number;
        v_name := v_acc.dana_name;
    END IF;

    v_gross := p_coins * v_rate;
    -- (b) DIPULIHKAN: bulatkan ke atas agar SAMA dengan preview client
    -- (WithdrawQuote.calc memakai round()). Dulu server memotong lewat
    -- pembagian integer → dialog konfirmasi menjanjikan Rp 1 lebih besar.
    v_fee := round((v_gross * v_fee_pct) / 100.0);
    IF v_fee < v_fee_min THEN v_fee := v_fee_min; END IF;
    IF v_fee > v_gross THEN v_fee := v_gross; END IF;
    v_net := v_gross - v_fee;

    INSERT INTO public.withdrawal_requests
        (user_id, coin_amount, payout_idr, gross_idr, fee_idr, rate,
         status, pay_method, pay_account, pay_holder)
    VALUES
        (v_uid, p_coins, v_net, v_gross, v_fee, v_rate,
         'pending', 'ewallet', v_num, v_name)
    RETURNING id INTO v_req_id;

    -- SATU-SATUNYA titik debit. HANYA bucket `earned`.
    PERFORM public.ledger_spend_earned(v_uid, 'withdraw', p_coins, v_req_id::text);

    INSERT INTO public.point_events (user_id, event, amount, metadata)
    VALUES (v_uid, 'withdraw', -p_coins, jsonb_build_object('request', v_req_id));

    RETURN jsonb_build_object('ok', true, 'id', v_req_id,
        'coins', p_coins, 'rate', v_rate,
        'gross_idr', v_gross, 'fee_idr', v_fee, 'net_idr', v_net,
        'dana_number', v_num, 'dana_name', v_name,
        'status', 'pending');
END;
$function$;

-- ── 4. Approve admin ────────────────────────────────────────────────────
-- menyentuh: admin_withdraw_process
create or replace function public.admin_withdraw_process(p_request_id uuid, p_approve boolean, p_note text DEFAULT NULL::text, p_tx_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_admin_email text := coalesce(auth.email(), '');
    v_req record;
    v_taken record;
    v_refunded bigint := 0;
    v_new_points int;
BEGIN
    IF v_admin_email <> 'zunixe@gmail.com' THEN
        RAISE EXCEPTION 'NOT_ADMIN: hanya admin';
    END IF;

    -- Kunci baris + wajib masih pending → approve/reject ganda ditolak.
    SELECT * INTO v_req
      FROM public.withdrawal_requests
     WHERE id = p_request_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    IF v_req.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED',
            'status', v_req.status);
    END IF;

    IF NOT p_approve THEN
        -- Koin sudah didebit saat request → kembalikan PERSIS sebesar baris
        -- ledger 'withdraw' milik pengajuan ini (reverse per bucket).
        FOR v_taken IN
            SELECT bucket, (-sum(amount))::int AS amt
              FROM public.coin_ledger
             WHERE user_id = v_req.user_id
               AND type = 'withdraw'
               AND ref_id = v_req.id::text
             GROUP BY bucket
            HAVING -sum(amount) > 0
        LOOP
            PERFORM public.ledger_credit(v_req.user_id, v_taken.bucket,
                'withdraw_refund', v_taken.amt, v_req.id::text,
                jsonb_build_object('reason', 'reject', 'note', p_note));
            v_refunded := v_refunded + v_taken.amt;
        END LOOP;

        UPDATE public.withdrawal_requests
        SET status = 'rejected',
            admin_note = nullif(trim(coalesce(p_note, '')), ''),
            reviewed_by = auth.uid(),
            reviewed_at = now(),
            updated_at = now()
        WHERE id = p_request_id AND status = 'pending';

        RETURN jsonb_build_object('ok', true, 'status', 'rejected',
            'refunded', v_refunded);
    END IF;

    -- Approve: TIDAK ada debit. Koin sudah keluar di request_withdraw.
    -- B4: wajib ada bukti transfer (tx_id) agar bisa diaudit ulang.
    IF nullif(trim(coalesce(p_tx_id, '')), '') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'TX_ID_REQUIRED');
    END IF;

    -- 2026-11-10: cek ulang saat approve — refund/penahanan bisa datang
    -- SETELAH request dibuat (mis. refund Play hari ke-10).
    IF EXISTS (SELECT 1 FROM public.fraud_holds
                WHERE user_id = v_req.user_id AND resolved_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'UNDER_REVIEW');
    END IF;

    UPDATE public.withdrawal_requests
    SET status = 'paid',
        admin_note = nullif(trim(coalesce(p_note, '')), ''),
        tx_id = trim(p_tx_id),
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id AND status = 'pending';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED');
    END IF;

    SELECT points INTO v_new_points FROM public.profiles WHERE id = v_req.user_id;

    RETURN jsonb_build_object('ok', true, 'status', 'paid',
        'coins', v_req.coin_amount, 'net_idr', v_req.payout_idr,
        'tx_id', trim(p_tx_id),
        'remaining_points', v_new_points, 'debited', 0);
END;
$function$;

-- ── 5. Langganan: harga terkunci saat klik ──────────────────────────────
drop function if exists public.subscribe_creator(uuid, integer);
-- menyentuh: subscribe_creator
create or replace function public.subscribe_creator(p_creator uuid, p_periods integer DEFAULT 1, p_expected_price integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); price int; cut_pct int; duration_days int; periods int;
  points_on boolean; am_registered boolean; remaining int; cost int; cut int; net int;
  expire timestamptz;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_creator is null or p_creator = me then raise exception 'Invalid creator'; end if;

  select is_registered into am_registered from profiles where id = me;
  if am_registered is not true then raise exception 'Subscriber must be registered'; end if;

  select subscription_price into price from profiles where id = p_creator;
  if price is null or price <= 0 then raise exception 'Not a paid creator'; end if;
  -- 2026-11-10: harga yang dilihat user di layar HARUS sama — kreator tak
  -- bisa menaikkan harga tepat sebelum user menekan Langganan.
  if p_expected_price is not null and p_expected_price <> price then
    raise exception 'PRICE_CHANGED';
  end if;

  select points_enabled, subscribe_cut_pct, subscription_duration_days
    into points_on, cut_pct, duration_days from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  periods := greatest(coalesce(p_periods, 1), 1);
  if periods > 12 then raise exception 'Invalid periods'; end if;

  cost := price * periods;
  cut := (cost * cut_pct) / 100;
  net := cost - cut;

  -- Paid-only: hanya topup+earned (bonus tidak berlaku).
  remaining := public.ledger_spend_paid(me, 'subscribe', cost, p_creator::text);

  -- Perpanjang / buat subscription.
  select expires_at into expire from subscriptions
    where subscriber_id = me and creator_id = p_creator;
  if expire is null or expire < now() then
    expire := now();
  end if;
  expire := expire + make_interval(days => duration_days * periods);

  insert into subscriptions (subscriber_id, creator_id, price, starts_at, expires_at)
    values (me, p_creator, price, now(), expire)
    on conflict (subscriber_id, creator_id)
    do update set price = excluded.price, expires_at = excluded.expires_at;

  if net > 0 then
    perform public.ledger_credit(p_creator, 'earned', 'subscribe_income', net,
      me::text, jsonb_build_object('subscriber', me, 'periods', periods));
  end if;
  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('subscribe_cut', cut, me, p_creator, p_creator::text,
              jsonb_build_object('gross', cost, 'net', net, 'pct', cut_pct, 'periods', periods));
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (me, 'subscribe', -cost, jsonb_build_object('creator', p_creator, 'periods', periods));

  return jsonb_build_object('ok', true, 'points', remaining, 'expires_at', expire,
    'net', net, 'cut', cut);
end; $function$;
revoke execute on function public.subscribe_creator(uuid, integer, integer) from public, anon;
grant execute on function public.subscribe_creator(uuid, integer, integer) to authenticated;

-- ── 6. send_gift wallet lock ────────────────────────────────────────────
-- menyentuh: send_gift
create or replace function public.send_gift(p_chat_id text, p_receiver_id uuid, p_gift_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int;
  my_name text; my_gender text; am_registered boolean;
  n int; cut int; net int;
  paid int; remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  -- 2026-11-10: serialkan debit per user (sama dgn ledger_spend_paid dst);
  -- juga menutup balapan cek batas transaksi/jam.
  perform pg_advisory_xact_lock(hashtext('wallet:' || uid::text));
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;
  select points_enabled, coalesce(gift_cut_pct,30)
    into points_on, cut_pct from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;
  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;
  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;
  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins;
  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;
  if exists (select 1 from public.blocks b
      where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
         or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- 2026-10-31: gift WAJIB pakai koin beli/penghasilan (topup + earned).
  -- Koin gratis (`bonus`) TIDAK boleh dipakai — mencegah koin gratis male
  -- berubah menjadi saldo withdrawable female (rugi platform).
  select coalesce(sum(amount) filter (where bucket='topup'), 0)
       + coalesce(sum(amount) filter (where bucket='earned'), 0)
    into paid
    from coin_ledger where user_id = uid;

  if paid < n then
    raise exception 'Gift membutuhkan koin beli/penghasilan (top-up dulu)'
      using errcode = '22023';
  end if;

  -- Potong dari topup dulu, lalu earned.
  declare
    take_topup int := least((select coalesce(sum(amount) filter (where bucket='topup'),0)
                              from coin_ledger where user_id = uid), n);
    take_earned int := n - take_topup;
  begin
    if take_topup > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (uid,'topup','gift_sent',-take_topup,p_chat_id);
    end if;
    if take_earned > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (uid,'earned','gift_sent',-take_earned,p_chat_id);
    end if;
  end;

  remaining := public.wallet_sync_points(uid);

  -- Platform ambil cut; penerima SELALU bucket `earned`.
  cut := (n * cut_pct) / 100;
  net := n - cut;

  if net > 0 then
    perform public.ledger_credit(p_receiver_id, 'earned', 'gift_recv', net,
      p_chat_id, jsonb_build_object('gift', p_gift_id, 'from', uid, 'tier', 'paid'));
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
              jsonb_build_object('gift', p_gift_id, 'gross', n, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n, jsonb_build_object('gift', p_gift_id, 'tier', 'paid')),
           (p_receiver_id, 'gift_recv', net,
            jsonb_build_object('gift', p_gift_id, 'tier', 'paid'));

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut, 'tier', 'paid');
end; $function$;

-- ── 7. Token push hanya untuk fungsi internal ──────────────────────────
revoke execute on function public.user_fcm_tokens(uuid) from public, anon, authenticated;
