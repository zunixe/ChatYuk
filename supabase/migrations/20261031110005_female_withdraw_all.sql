-- ══════════════════════════════════════════════════════════════════════
-- Female: SEMUA koin bisa di-withdraw + tutup jalur bocor koin gratis
--
-- Keputusan user (2026-10-31): "female koinnya harusnya semua bisa di
-- withdrawal" — tidak ada lagi bucket `bonus` yang menganggur untuk female.
--
-- Agar aman (platform tidak rugi), jalur yang membuat koin GRATIS (`bonus`)
-- mengalir ke female DITUTUP dulu:
--
--   1. `send_gift`  — BUG: tier `bonus` memberi penerima `n × 3` koin
--      (3× nilai gift!) tanpa potongan platform. Koin gratis male jadi
--      saldo female → kalau bisa ditarik = rugi Rp 2.100 per gift 100 koin.
--      → Tier `bonus` DIHAPUS. Gift wajib pakai koin beli/penghasilan.
--
--   2. `unlock_photo` — tier `bonus` mengredit pemilik foto ke bucket
--      `bonus`. → Tier `bonus` DIHAPUS. Unlock foto wajib koin beli.
--
-- Setelah ini, female HANYA pernah menerima bucket `earned` (dari call,
-- gift, unlock foto, dan reward misi) → "semua koin withdrawable" aman.
--
--   3. `request_withdraw`      — validasi terhadap TOTAL saldo ( semua bucket)
--   4. `admin_withdraw_process`— debit PROPORSIONAL dari semua bucket
--   5. `get_earnings_summary`  — `withdrawable` = total saldo
-- ══════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════
-- 1. send_gift — hapus tier bonus (gift wajib koin beli/penghasilan)
--    FROZEN → header wajib.
-- ══════════════════════════════════════════════════════════════════════
-- menyentuh: send_gift
CREATE OR REPLACE FUNCTION public.send_gift(p_chat_id text, p_receiver_id uuid, p_gift_id text)
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

-- ══════════════════════════════════════════════════════════════════════
-- 2. unlock_photo — hapus tier bonus (unlock wajib koin beli)
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.unlock_photo(p_photo_id text, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  points_on boolean; once_cost int; perm_cost int; owner_pct int;
  cost int; owner_id uuid; owner_share int; remaining int;
  paid int;
  take_topup int; take_earned int;
  res jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select points_enabled, photo_unlock_once, photo_unlock_perm, photo_unlock_owner_pct
    into points_on, once_cost, perm_cost, owner_pct
    from app_settings where id = 'global';

  if points_on is false then
    return jsonb_build_object('ok', true, 'tier', 'free', 'points',
      (select points from profiles where id = me));
  end if;

  cost := case when p_mode = 'perm' then coalesce(perm_cost,20)
               else coalesce(once_cost,5) end;

  -- Pemilik foto.
  select user_id into owner_id from public.user_photos where id = p_photo_id;
  if owner_id is null then
    raise exception 'Photo not found';
  end if;

  -- 2026-10-31: unlock WAJIB koin beli/penghasilan. Koin gratis (`bonus`)
  -- tidak boleh — mencegah koin gratis jadi income withdrawable female.
  select coalesce(sum(amount) filter (where bucket='topup'), 0)
       + coalesce(sum(amount) filter (where bucket='earned'), 0)
    into paid
    from coin_ledger where user_id = me;

  if paid < cost then
    raise exception 'Not enough points';
  end if;

  take_topup := least((select coalesce(sum(amount) filter (where bucket='topup'),0)
                        from coin_ledger where user_id = me), cost);
  take_earned := cost - take_topup;

  if take_topup > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (me,'topup','photo_unlock',-take_topup,p_photo_id);
  end if;
  if take_earned > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (me,'earned','photo_unlock',-take_earned,p_photo_id);
  end if;

  remaining := public.wallet_sync_points(me);

  -- Pemilik foto dapat bagiannya (bucket `earned`).
  owner_share := (cost * owner_pct) / 100;
  if owner_share > 0 and owner_id <> me then
    perform public.ledger_credit(owner_id, 'earned', 'photo_unlock_income',
      owner_share, p_photo_id,
      jsonb_build_object('from', me, 'mode', p_mode, 'gross', cost));
  end if;

  -- Catat revenue platform.
  insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
    values ('photo_unlock', cost - owner_share, me, owner_id, p_photo_id,
            jsonb_build_object('mode', p_mode, 'gross', cost,
                               'owner_share', owner_share));

  res := jsonb_build_object('ok', true, 'tier', 'paid', 'points', remaining,
    'owner_share', owner_share);

  -- Tandai akses (kalau tabel akses ada).
  begin
    insert into public.photo_access(photo_id, user_id, mode)
    values (p_photo_id, me, p_mode)
    on conflict do nothing;
  exception when others then
    null; -- tabel opsional
  end;

  return res;
end; $function$;

-- ══════════════════════════════════════════════════════════════════════
-- 3. request_withdraw — female: validasi TOTAL saldo (semua bucket)
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_withdraw(
    p_coins int,
    p_dana_number text DEFAULT NULL,
    p_dana_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
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
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

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
           coalesce(withdraw_min_account_age_hours, 72)
      INTO v_min_coins, v_rate, v_fee_pct, v_fee_min,
           v_max_day, v_min_interval, v_min_age
      FROM public.app_settings WHERE id = 'global';

    IF p_coins IS NULL OR p_coins < v_min_coins THEN
        RETURN jsonb_build_object('ok', false, 'error', 'BELOW_MINIMUM',
            'min_coins', v_min_coins);
    END IF;

    -- 2026-10-31: female boleh menarik SEMUA koinnya (total saldo),
    -- bukan hanya bucket `earned`. Jalur masuk koin gratis ke female
    -- sudah ditutup (send_gift & unlock_photo wajib koin beli).
    SELECT coalesce(sum(amount), 0) INTO v_total
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

    SELECT count(*) INTO v_today_count
      FROM public.withdrawal_requests
     WHERE user_id = v_uid AND created_at >= current_date;
    IF v_today_count >= v_max_day THEN
        RETURN jsonb_build_object('ok', false, 'error', 'DAILY_LIMIT',
            'max_per_day', v_max_day);
    END IF;

    SELECT max(created_at) INTO v_last_req
      FROM public.withdrawal_requests WHERE user_id = v_uid;
    IF v_last_req IS NOT NULL
       AND v_last_req > now() - make_interval(hours => v_min_interval) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'TOO_SOON',
            'min_interval_hours', v_min_interval);
    END IF;

    -- Akun DANA: pakai yang dikirim, atau yang tersimpan.
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
        INSERT INTO public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
        VALUES (v_uid, v_num, v_name, now())
        ON CONFLICT (user_id) DO UPDATE SET
            dana_number = excluded.dana_number,
            dana_name = excluded.dana_name,
            updated_at = now();
    ELSE
        SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'error', 'NO_ACCOUNT');
        END IF;
        v_num := v_acc.dana_number;
        v_name := v_acc.dana_name;
    END IF;

    v_gross := p_coins * v_rate;
    v_fee := greatest((v_gross * v_fee_pct) / 100, v_fee_min);
    IF v_fee > v_gross THEN v_fee := v_gross; END IF;
    v_net := v_gross - v_fee;

    INSERT INTO public.withdrawal_requests
        (user_id, coin_amount, payout_idr, gross_idr, fee_idr, rate,
         status, pay_method, pay_account, pay_holder)
    VALUES
        (v_uid, p_coins, v_net, v_gross, v_fee, v_rate,
         'pending', 'ewallet', v_num, v_name)
    RETURNING id INTO v_req_id;

    RETURN jsonb_build_object('ok', true, 'id', v_req_id,
        'coins', p_coins, 'rate', v_rate,
        'gross_idr', v_gross, 'fee_idr', v_fee, 'net_idr', v_net,
        'dana_number', v_num, 'dana_name', v_name,
        'status', 'pending');
END;
$$;

-- ══════════════════════════════════════════════════════════════════════
-- 4. admin_withdraw_process — debit PROPORSIONAL dari semua bucket
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_withdraw_process(
    p_request_id uuid,
    p_approve boolean,
    p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_admin_email text := coalesce(auth.email(), '');
    v_req record;
    v_bonus int;
    v_topup int;
    v_earned int;
    v_total int;
    v_take_bonus int;
    v_take_topup int;
    v_take_earned int;
    v_new_points int;
BEGIN
    IF v_admin_email <> 'zunixe@gmail.com' THEN
        RAISE EXCEPTION 'NOT_ADMIN: hanya admin';
    END IF;

    SELECT * INTO v_req FROM public.withdrawal_requests WHERE id = p_request_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    IF v_req.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_PROCESSED',
            'status', v_req.status);
    END IF;

    IF NOT p_approve THEN
        UPDATE public.withdrawal_requests
        SET status = 'rejected',
            admin_note = nullif(trim(coalesce(p_note, '')), ''),
            reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
            reviewed_at = now(),
            updated_at = now()
        WHERE id = p_request_id;
        RETURN jsonb_build_object('ok', true, 'status', 'rejected');
    END IF;

    -- Saldo per bucket SAAT INI (bisa berubah sejak request).
    SELECT coalesce(sum(amount) filter (where bucket='bonus'), 0),
           coalesce(sum(amount) filter (where bucket='topup'), 0),
           coalesce(sum(amount) filter (where bucket='earned'), 0)
      INTO v_bonus, v_topup, v_earned
      FROM public.coin_ledger WHERE user_id = v_req.user_id;

    v_total := v_bonus + v_topup + v_earned;
    IF v_total < v_req.coin_amount THEN
        UPDATE public.withdrawal_requests
        SET status = 'rejected',
            admin_note = 'saldo tidak cukup saat approve',
            reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
            reviewed_at = now(),
            updated_at = now()
        WHERE id = p_request_id;
        RETURN jsonb_build_object('ok', false, 'error', 'INSUFFICIENT_AT_APPROVE',
            'balance', v_total, 'needed', v_req.coin_amount);
    END IF;

    -- Bagi proporsional: tiap bucket menyumbang sebanding porsinya.
    v_take_bonus := (v_req.coin_amount * v_bonus) / v_total;
    v_take_topup := (v_req.coin_amount * v_topup) / v_total;
    v_take_earned := v_req.coin_amount - v_take_bonus - v_take_topup;
    -- Koreksi pembulatan: jangan melebihi saldo bucket.
    IF v_take_bonus > v_bonus THEN
        v_take_earned := v_take_earned + (v_take_bonus - v_bonus);
        v_take_bonus := v_bonus;
    END IF;
    IF v_take_topup > v_topup then
        v_take_earned := v_take_earned + (v_take_topup - v_topup);
        v_take_topup := v_topup;
    END IF;

    IF v_take_bonus > 0 then
        insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
        values (v_req.user_id,'bonus','withdraw',-v_take_bonus, v_req.id::text,
          jsonb_build_object('gross_idr', v_req.gross_idr, 'fee_idr', v_req.fee_idr,
                             'net_idr', v_req.payout_idr, 'pay', 'dana',
                             'account', v_req.pay_account));
    end if;
    IF v_take_topup > 0 then
        insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
        values (v_req.user_id,'topup','withdraw',-v_take_topup, v_req.id::text,
          jsonb_build_object('gross_idr', v_req.gross_idr, 'fee_idr', v_req.fee_idr,
                             'net_idr', v_req.payout_idr, 'pay', 'dana',
                             'account', v_req.pay_account));
    end if;
    IF v_take_earned > 0 then
        insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
        values (v_req.user_id,'earned','withdraw',-v_take_earned, v_req.id::text,
          jsonb_build_object('gross_idr', v_req.gross_idr, 'fee_idr', v_req.fee_idr,
                             'net_idr', v_req.payout_idr, 'pay', 'dana',
                             'account', v_req.pay_account));
    end if;

    SELECT points INTO v_new_points FROM public.profiles WHERE id = v_req.user_id;

    UPDATE public.withdrawal_requests
    SET status = 'paid',
        admin_note = nullif(trim(coalesce(p_note, '')), ''),
        reviewed_by = (SELECT id FROM public.profiles WHERE email = v_admin_email LIMIT 1),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id;

    RETURN jsonb_build_object('ok', true, 'status', 'paid',
        'coins', v_req.coin_amount, 'net_idr', v_req.payout_idr,
        'remaining_points', v_new_points,
        'debited', jsonb_build_object('bonus', v_take_bonus,
                                      'topup', v_take_topup,
                                      'earned', v_take_earned));
END;
$$;

-- ══════════════════════════════════════════════════════════════════════
-- 5. get_earnings_summary — withdrawable = TOTAL saldo (female)
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_earnings_summary(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result jsonb;
    v_total bigint;
    v_weekly bigint;
    v_today bigint;
    v_private_call bigint := 0;
    v_match_call bigint := 0;
    v_message bigint := 0;
    v_gift bigint;
    v_mission bigint;
    v_bonus bigint;
    v_other bigint;
    v_withdrawable bigint;
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
BEGIN
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= date_trunc('week', now())), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= current_date), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'gift_recv'), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'mission_reward'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type IN ('signup','welcome_anon','daily_login','one_time',
                           'new_chat','room_read','photo_upload')), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type NOT IN ('gift_recv','mission_reward','signup','welcome_anon',
                               'daily_login','one_time','new_chat','room_read',
                               'photo_upload')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission, v_bonus, v_other
    FROM public.coin_ledger
    WHERE user_id = p_user_id;

    -- 2026-10-31: female boleh menarik SEMUA koinnya. Jalur masuk koin
    -- gratis ke female sudah ditutup, jadi total saldo = aman ditarik.
    v_withdrawable := v_total;

    SELECT
        COUNT(*) FILTER (WHERE call_type = 'video'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE call_type = 'video' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint,
        COUNT(*) FILTER (WHERE kind = 'random'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE kind = 'random' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint
    INTO v_video_calls, v_video_seconds, v_match_calls, v_match_seconds
    FROM public.calls
    WHERE (caller_id = p_user_id OR callee_id = p_user_id)
      AND status = 'ended';

    SELECT COUNT(*), COUNT(*) FILTER (WHERE answered_at IS NOT NULL)
    INTO v_private_total, v_private_answered
    FROM public.calls
    WHERE callee_id = p_user_id
      AND coalesce(kind, '') <> 'random'
      AND status = 'ended';

    result := jsonb_build_object(
        'total_earnings', v_total,
        'weekly_earnings', v_weekly,
        'today_earnings', v_today,
        'withdrawable', v_withdrawable,
        'breakdown', jsonb_build_object(
            'private_call', v_private_call,
            'match_call', v_match_call,
            'message', v_message,
            'gift', v_gift,
            'mission', v_mission,
            'bonus', v_bonus,
            'other', v_other
        ),
        'stats', jsonb_build_object(
            'video_call_count', v_video_calls,
            'video_call_seconds', v_video_seconds,
            'match_call_count', v_match_calls,
            'match_call_seconds', v_match_seconds,
            'avg_match_seconds', CASE
                WHEN v_match_calls > 0 THEN (v_match_seconds / v_match_calls)::bigint
                ELSE 0 END,
            'private_call_total', v_private_total,
            'private_call_answered', v_private_answered,
            'private_answer_rate', CASE
                WHEN v_private_total > 0
                THEN round((v_private_answered::numeric / v_private_total) * 100)
                ELSE 0 END
        )
    );

    RETURN result;
END;
$$;

-- Grants
REVOKE EXECUTE ON FUNCTION public.send_gift(text, uuid, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.unlock_photo(text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.request_withdraw(int, text, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.admin_withdraw_process(uuid, boolean, text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.send_gift(text, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unlock_photo(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_withdraw(int, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_withdraw_process(uuid, boolean, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;
