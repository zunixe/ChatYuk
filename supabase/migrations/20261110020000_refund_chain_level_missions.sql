-- ══════════════════════════════════════════════════════════════════════
-- Review ulang ekonomi (2026-11-10) — Fase 3+4: refund berantai, level,
-- refund chat, misi.
-- 1. reverse_play_topup: tahan penerima berantai (kedalaman 3) + cabut
--    level & hadiah level pembeli.
-- 2. Level = koin dari topup_orders status 'paid' (level_paid_coins).
--    Menutup panen level via deduct/refund_chat_point & level yang tetap
--    setelah refund. (Live 2026-11-10: belum ada topup → tak ada level turun.)
-- 3. refund_chat_point: maks 10/jam.
-- 4. update_mission_progress: kenaikan dari klien dibatasi waktu nyata.
-- ══════════════════════════════════════════════════════════════════════

alter table public.user_missions
  add column if not exists last_increment_at timestamptz;

create or replace function public.level_paid_coins(p_uid uuid)
returns int
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(sum(coins), 0)::int
    from public.topup_orders
   where user_id = p_uid and status = 'paid';
$function$;
revoke execute on function public.level_paid_coins(uuid) from public, anon, authenticated;

-- Setelah refund: turunkan level & tarik hadiah level di atas level baru
-- (sebatas saldo bonus — tak pernah negatif).
create or replace function public.level_recompute_after_refund(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lvl int; r record; b int; take int; v_taken int := 0;
begin
  select coalesce(max(level), 0) into v_lvl
    from public.level_config where topup_coins <= public.level_paid_coins(p_uid);

  perform pg_advisory_xact_lock(hashtext('wallet:' || p_uid::text));
  for r in
    select l.ref_id, sum(l.amount)::int as amt
      from public.coin_ledger l
     where l.user_id = p_uid and l.type in ('level_reward', 'level_reward_reversal')
       and l.ref_id like 'level\_%' escape '\'
     group by l.ref_id
    having sum(l.amount) > 0
  loop
    if substring(r.ref_id from 7)::int <= v_lvl then continue; end if;
    select coalesce(sum(amount), 0) into b
      from public.coin_ledger where user_id = p_uid and bucket = 'bonus';
    take := least(greatest(b, 0), r.amt);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (p_uid, 'bonus', 'level_reward_reversal', -take, r.ref_id,
              jsonb_build_object('reason', 'play_refund'));
      v_taken := v_taken + take;
    end if;
  end loop;

  update public.user_level_state
     set level = v_lvl,
         reward_granted_level = least(reward_granted_level, v_lvl)
   where user_id = p_uid;
  return jsonb_build_object('level', v_lvl, 'reclaimed', v_taken);
end;
$function$;
revoke execute on function public.level_recompute_after_refund(uuid) from public, anon, authenticated;

create or replace function public.reverse_play_topup(p_purchase_token text, p_reason text DEFAULT 'voided'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  o record; t int; e int; take int; need int; n_flag int := 0;
begin
  select * into o from public.topup_orders
   where purchase_token = p_purchase_token for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;
  if o.status = 'refunded' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  perform pg_advisory_xact_lock(hashtext('wallet:' || o.user_id::text));
  select coalesce(sum(amount) filter (where bucket = 'topup'), 0),
         coalesce(sum(amount) filter (where bucket = 'earned'), 0)
    into t, e
    from public.coin_ledger where user_id = o.user_id;

  need := o.coins;
  take := least(greatest(t, 0), need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
    values (o.user_id, 'topup', 'play_refund', -take, o.id,
            jsonb_build_object('reason', p_reason));
    need := need - take;
  end if;
  take := least(greatest(e, 0), need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
    values (o.user_id, 'earned', 'play_refund', -take, o.id,
            jsonb_build_object('reason', p_reason));
    need := need - take;
  end if;

  update public.topup_orders
     set status = 'refunded', refunded_at = now(), refund_shortfall = need
   where id = o.id;

  -- 2026-11-10: tahan pembeli + penerima BERANTAI (A→B→C, kedalaman 3)
  -- sejak pembelian — dulu hanya penerima langsung, jadi koin bisa
  -- "dicuci" lewat satu akun perantara.
  insert into public.fraud_holds (user_id, reason, ref_id)
  select distinct u, 'play_refund', o.id
    from (
      with recursive chain(u, depth) as (
        select o.user_id, 0
        union
        select pr.to_user, ch.depth + 1
          from chain ch
          join public.platform_revenue pr on pr.from_user = ch.u
         where pr.to_user is not null
           and pr.created_at >= coalesce(o.paid_at, o.created_at)
           and ch.depth < 3
      )
      select u from chain
    ) x
  on conflict do nothing;
  get diagnostics n_flag = row_count;

  -- Level & hadiah level ikut dicabut (dihitung dari order paid).
  perform public.level_recompute_after_refund(o.user_id);

  return jsonb_build_object('ok', true, 'order_id', o.id, 'coins', o.coins,
    'shortfall', need, 'flagged', n_flag);
end;
$function$;

-- menyentuh: get_my_level
create or replace function public.get_my_level()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  cum int;
  lvl int;
  st public.user_level_state;
  l record;
  ladder jsonb;
  just_rewarded jsonb := '[]'::jsonb;
  points_on boolean;
  v_gender text;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  -- 2026-11-10: kumulatif = koin dari ORDER pembelian berstatus paid
  -- (bukan ledger) — refund chat (`spend_refund`) dulu menulis kredit
  -- topup positif → level bisa dipanen; order refunded juga tak dihitung.
  cum := public.level_paid_coins(me);

  select coalesce(max(level), 0) into lvl
    from level_config where topup_coins <= cum;

  select gender into v_gender from profiles where id = me;

  select points_enabled into points_on from app_settings where id = 'global';

  -- State + grant reward (idempoten): lock baris agar panggilan paralel
  -- tidak dobel-credit (pola advisory-lock ala ledger_spend).
  select * into st from user_level_state where user_id = me for update;
  if not found then
    insert into user_level_state (user_id, level, reward_granted_level)
      values (me, lvl, 0)
      on conflict (user_id) do nothing;
    select * into st from user_level_state where user_id = me for update;
  end if;

  -- Reward hanya MALE (fitur My Level = male only) + kill-switch ekonomi.
  if lvl > st.reward_granted_level
     and v_gender = 'male'
     and points_on is not false then
    for l in select level, reward_coins from level_config
             where level > st.reward_granted_level
               and level <= lvl
               and reward_coins > 0
             order by level
    loop
      perform public.ledger_credit(me, 'bonus', 'level_reward',
        l.reward_coins, 'level_' || l.level,
        jsonb_build_object('level', l.level));
      just_rewarded := just_rewarded || jsonb_build_array(
        jsonb_build_object('level', l.level, 'coins', l.reward_coins));
    end loop;
    update user_level_state
       set reward_granted_level = lvl, level = lvl, updated_at = now()
     where user_id = me;
  else
    update user_level_state
       set level = lvl, updated_at = now()
     where user_id = me and level is distinct from lvl;
  end if;

  select jsonb_agg(jsonb_build_object(
           'level', x.level, 'topup_coins', x.topup_coins,
           'reward_coins', x.reward_coins) order by x.level)
    into ladder
    from level_config x;

  return jsonb_build_object(
    'level', lvl,
    'cumulative', cum,
    'next_level', (select min(level) from level_config where topup_coins > cum),
    'next_at',    (select min(topup_coins) from level_config where topup_coins > cum),
    'remaining',  coalesce((select min(topup_coins) from level_config where topup_coins > cum), 0) - cum,
    'ladder', coalesce(ladder, '[]'::jsonb),
    'just_rewarded', just_rewarded
  );
end;
$function$;

-- menyentuh: get_user_level
create or replace function public.get_user_level(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('level', case
    when (select gender from profiles where id = p_user) is distinct from 'male' then 0
    else coalesce((
      select max(lc.level)
        from level_config lc
       where lc.topup_coins <= (
         select public.level_paid_coins(p_user)
       )
    ), 0)
  end);
$function$;

-- menyentuh: refund_chat_point
create or replace function public.refund_chat_point(msg_type text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid     uuid := auth.uid();
  v_enabled boolean;
  v_latest  timestamptz;
begin
  if v_uid is null then
    return 0;
  end if;

  -- Kill-switch: tanpa poin aktif tidak ada debit -> tidak ada yang direfund.
  select points_enabled into v_enabled
    from public.app_settings where id = 'global';
  if coalesce(v_enabled, false) is not true then
    return public.wallet_sync_points(v_uid);
  end if;

  -- Serialisasi per user: dua panggilan paralel tidak boleh sama-sama lolos
  -- pengecekan "belum pernah direfund".
  perform pg_advisory_xact_lock(hashtext('refund_chat_point:' || v_uid::text));

  -- 2026-11-10: batasi 10 refund/jam — refund tak memeriksa kegagalan kirim
  -- sungguhan, jadi tanpa batas bisa diputar ulang tanpa henti.
  if (select count(*) from public.coin_ledger
       where user_id = v_uid and type = 'spend_refund'
         and created_at > now() - interval '1 hour') >= 10 then
    return public.wallet_sync_points(v_uid);
  end if;

  -- Grup spend terbaru yang BELUM di-refund, dalam jendela 10 menit.
  select l.created_at into v_latest
    from public.coin_ledger l
   where l.user_id = v_uid
     and l.type = 'spend_chat'
     and l.ref_id = msg_type
     and l.created_at > now() - interval '10 minutes'
     and not exists (
       select 1 from public.coin_ledger r
        where r.user_id = v_uid
          and r.type = 'spend_refund'
          and r.metadata->>'refund_of' = l.id::text
     )
   order by l.created_at desc
   limit 1;

  if v_latest is null then
    return public.wallet_sync_points(v_uid);
  end if;

  insert into public.coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
  select l.user_id, l.bucket, 'spend_refund', -l.amount, l.ref_id,
         jsonb_build_object('refunded_msg_type', msg_type, 'refund_of', l.id::text)
    from public.coin_ledger l
   where l.user_id = v_uid
     and l.type = 'spend_chat'
     and l.ref_id = msg_type
     and l.created_at = v_latest
     and not exists (
       select 1 from public.coin_ledger r
        where r.user_id = v_uid
          and r.type = 'spend_refund'
          and r.metadata->>'refund_of' = l.id::text
     )
  on conflict do nothing;

  return public.wallet_sync_points(v_uid);
end;
$function$;

-- menyentuh: update_mission_progress
create or replace function public.update_mission_progress(p_user_id uuid, p_mission_key text, p_increment integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission record;
    v_period date;
    v_progress int;
    v_completed boolean;
    v_inc int;
    v_last timestamptz;
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

    v_period := CASE WHEN v_mission.is_daily THEN CURRENT_DATE ELSE NULL END;

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
