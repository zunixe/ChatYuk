-- ============================================================
-- 20261107000000_econ_antifraud_phaseb.sql
-- Fase B review ekonomi — anti-fraud withdraw & transfer koin.
--
-- menyentuh: send_coins (FROZEN — body diambil dari definisi LIVE
--   pg_get_functiondef 2026-11-03, hanya tambah cabang cut;
--   request_withdraw & admin_withdraw_process BUKAN FROZEN tapi
--   body juga diambil dari live, bukan migrasi lama).
--
-- Isi:
--  B1. send_coins: penerima menerima NET = amount*(100-cut)/100 ke
--      `earned`; cut (default 30%, admin-tunable `coin_send_cut_pct`)
--      masuk platform_revenue source='coin_send_cut'. Menutup celah
--      pencucian "beli → kirim ke akun female sendiri → withdraw 100%
--      → refund Google" — sekarang hasil send_coins dipotong sama
--      seperti gift.
--  B2. Gerbang KYC withdraw: `withdraw_require_kyc` (default true).
--      request_withdraw menolak KYC_REQUIRED bila flag aktif dan user
--      belum punya kyc_requests status='approved'.
--  B3. Cooldown ganti nomor DANA: `withdraw_dana_change_cooldown_hours`
--      (default 168 jam = 7 hari). Mengganti nomor yang berbeda dari
--      withdraw_accounts yang tersimpan < cooldown ditolak
--      DANA_CHANGE_COOLDOWN (pola: request → ganti nomor → withdraw
--      ke rekening mule berbeda). Nomor sama/nama saja berubah → bebas.
--  B4. tx_id bukti transfer: admin_withdraw_process menerima
--      p_tx_id opsional (param baru ke-4, default null) → kolom
--      tx_id diisi saat approve. Signature lama (3 arg) di-drop —
--      dipanggil client hanya lewat named params, aman.
-- ============================================================

-- ── B0. Setting baru ─────────────────────────────────────────
alter table public.app_settings
  add column if not exists coin_send_cut_pct int not null default 30,
  add column if not exists withdraw_require_kyc boolean not null default true,
  add column if not exists withdraw_dana_change_cooldown_hours int not null default 168;

-- ════════════════════════════════════════════════════════════
-- B1. send_coins — potongan platform 30% (anti-pencucian)
-- ════════════════════════════════════════════════════════════
create or replace function public.send_coins(p_chat_id text, p_receiver_id uuid, p_amount integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
  v_cut_pct int; v_cut int; v_net int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;

  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- Hanya koin belian (topup+earned) — koin bonus TIDAK bisa ditransfer.
  remaining := public.ledger_spend_paid(uid, 'coin_sent', p_amount, p_chat_id);

  -- B1: potongan platform (default 30%). Penerima menerima NET ke
  -- `earned` — masih bisa di-withdraw, tapi hasil "pencucian" send_coins
  -- kini dipotong seperti gift sehingga refund-fraud tidak lagi gratis.
  select coalesce(coin_send_cut_pct, 30) into v_cut_pct
    from app_settings where id = 'global';
  v_cut := (p_amount * v_cut_pct) / 100;
  v_net := p_amount - v_cut;

  perform public.ledger_credit(p_receiver_id, 'earned', 'coin_received', v_net,
    p_chat_id, jsonb_build_object('from', uid,
      'gross', p_amount, 'cut', v_cut, 'pct', v_cut_pct));

  if v_cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
    values ('coin_send_cut', v_cut, uid, p_receiver_id, p_chat_id,
            jsonb_build_object('gross', p_amount, 'pct', v_cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', v_net);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
    'sent', p_amount, 'received', v_net, 'cut_pct', v_cut_pct);
end; $function$;

-- ════════════════════════════════════════════════════════════
-- B2 + B3. request_withdraw — KYC gate & cooldown nomor DANA
-- ════════════════════════════════════════════════════════════
create or replace function public.request_withdraw(p_coins integer, p_dana_number text DEFAULT NULL::text, p_dana_name text DEFAULT NULL::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
           coalesce(withdraw_dana_change_cooldown_hours, 168)
      INTO v_min_coins, v_rate, v_fee_pct, v_fee_min,
           v_max_day, v_min_interval, v_min_age,
           v_require_kyc, v_dana_cd_hours
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

    -- B2: Gerbang KYC — dipasang SETELAH semua validasi murah supaya
    -- error ordering tetap intuitif (BELOW_MINIMUM dkk menang dulu).
    -- Withdraw hanya untuk identitas terverifikasi saat flag aktif.
    IF v_require_kyc AND NOT EXISTS (
        SELECT 1 FROM public.kyc_requests
         WHERE user_id = v_uid AND status = 'approved') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'KYC_REQUIRED');
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

-- ════════════════════════════════════════════════════════════
-- B4. admin_withdraw_process — +p_tx_id (bukti transfer di approve)
-- Signature lama (uuid,bool,text) di-drop: client memanggil lewat
-- named params sehingga overload baru dengan default tetap cocok.
-- ════════════════════════════════════════════════════════════
drop function if exists public.admin_withdraw_process(uuid, boolean, text);

create or replace function public.admin_withdraw_process(
    p_request_id uuid, p_approve boolean,
    p_note text DEFAULT NULL::text, p_tx_id text DEFAULT NULL::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
            reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
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

    UPDATE public.withdrawal_requests
    SET status = 'paid',
        admin_note = nullif(trim(coalesce(p_note, '')), ''),
        tx_id = trim(p_tx_id),
        reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
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

-- ════════════════════════════════════════════════════════════
-- Config publik untuk UI: tambah flag KYC & cooldown + cut send_coins
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_withdraw_config()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'rate', coalesce(withdraw_rate_idr, 7),
        'min_coins', coalesce(withdraw_min_coins, 1500),
        'fee_pct', coalesce(withdraw_fee_pct, 5),
        'fee_min_idr', coalesce(withdraw_fee_min_idr, 1000),
        'max_per_day', coalesce(withdraw_max_per_day, 3),
        'min_interval_hours', coalesce(withdraw_min_interval_hours, 1),
        'min_account_age_hours', coalesce(withdraw_min_account_age_hours, 72),
        'require_kyc', coalesce(withdraw_require_kyc, true),
        'dana_change_cooldown_hours',
            coalesce(withdraw_dana_change_cooldown_hours, 168),
        'coin_send_cut_pct', coalesce(coin_send_cut_pct, 30)
    ) INTO result
    FROM public.app_settings WHERE id = 'global';

    RETURN coalesce(result, jsonb_build_object(
        'rate', 7, 'min_coins', 1500, 'fee_pct', 5, 'fee_min_idr', 1000,
        'max_per_day', 3, 'min_interval_hours', 1, 'min_account_age_hours', 72,
        'require_kyc', true, 'dana_change_cooldown_hours', 168,
        'coin_send_cut_pct', 30));
END;
$$;
