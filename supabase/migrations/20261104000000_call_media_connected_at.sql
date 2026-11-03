-- 2026-11-04: jangkar billing Random Match ke momen media CONNECT.
--
-- Latar: random_match_join menulis answered_at = now() SAAT pair terbentuk,
-- sebelum WebRTC connect (~2-8 dtk, bisa >30 dtk di jaringan buruk). Elapsed
-- billing dihitung dari answered_at → "gratis 30 detik" terpakai oleh waktu
-- setup media; kasus terburuk: media nyambung detik 35 → tick pertama
-- langsung menagih konek 10 + menit 1 padahal video baru tampil.
--
-- Perubahan:
--   1) calls.media_connected_at — stamp sekali saat ICE pertama connected.
--   2) touch_call(p_call_id, p_connected) — p_connected=true men-stamp kolom
--      (earliest menang lewat coalesce; heartbeat biasa tak menyentuhnya).
--   3) call_billing_tick — untuk kind='random' elapsed memakai
--      coalesce(media_connected_at, answered_at). Client lama yang tak
--      men-stamp tetap dihitung dari answered_at (fallback, bukan regresi).
--   4) random_match_join — precheck male naik ke PAID >= pair+konek supaya
--      match yang terbentuk dijamin bisa melewati 30 detik gratis (male
--      bonus-only tak bisa bayar konek → call dijamin mati di detik 30).
--
-- menyentuh: touch_call, call_billing_tick, random_match_join

-- ── 1) Kolom jangkar media-connect (additive) ──
alter table public.calls
  add column if not exists media_connected_at timestamptz;

-- ── 2) touch_call dengan flag p_connected ──
-- Overload 1-arg lama harus di-drop: fungsi baru ber-default-arg tetap cocok
-- untuk pemanggil lama rpc('touch_call', {p_call_id}), sedangkan dua overload
-- hidup berdampingan membuat resolusi PostgREST ambigu.
drop function if exists public.touch_call(uuid);

create or replace function public.touch_call(
  p_call_id uuid,
  p_connected boolean default false
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update public.calls
     set last_seen_at = now(),
         media_connected_at = case
           when p_connected then coalesce(media_connected_at, now())
           else media_connected_at
         end
   where id = p_call_id
     and ended_at is null
     and auth.uid() in (caller_id, callee_id);
end;
$function$;

-- Kembalikan ACL seperti versi lama (rpc dari client + service_role internal).
grant execute on function public.touch_call(uuid, boolean)
  to anon, authenticated, service_role;

-- ── 3) call_billing_tick — anchor elapsed ke media_connected_at ──
create or replace function public.call_billing_tick(p_call_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  c record;
  v_all boolean; v_anon boolean; points_on boolean;
  v_free_limit int; v_free_used int;
  v_caller_gender text;
  v_callee_gender text;
  feat text; unit_cost int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  remaining int; v_paid int; afford int; charge_n int;
  v_payer uuid; v_recipient uuid;
  v_connect_cost int := 0;
  v_connect_billed boolean := false;
  v_free_seconds_left int := 0;
  v_anchor timestamptz;
  -- Awal hari ini dalam zona waktu USER (Asia/Jakarta) sebagai timestamptz.
  -- PENTING: bandingkan timestamptz dengan timestamptz. Membandingkan
  -- `answered_at >= (…::date)` SALAH — Postgres menafsirkan date sebagai
  -- UTC midnight, jadi panggilan yang dijawab 23:29 UTC (06:29 WIB hari
  -- berikutnya) tidak terhitung. Ini bug nyata yang terbukti di test.
  v_day_start timestamptz :=
    (((now() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp
       AT TIME ZONE 'Asia/Jakarta');
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;
  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false),
         coalesce(points_enabled, true)
    into v_all, v_anon, points_on
    from app_settings where id = 'global';
  if not v_all then raise exception 'CALL_DISABLED'; end if;
  select gender into v_caller_gender from public.profiles where id = me;
  if not v_anon and not exists (
    select 1 from public.profiles p where p.id = me and p.is_registered) then
    raise exception 'CALL_REGISTERED_ONLY';
  end if;
  if points_on is false then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;
  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  -- Random: kedua peserta boleh tick (billing diarahkan ke payer).
  -- Private: tetap hanya caller yang men-tick (perilaku lama).
  if c.kind is distinct from 'random' and c.caller_id <> me then
    raise exception 'Only caller can be billed';
  end if;
  if c.kind = 'random' and me <> c.caller_id and me <> c.callee_id then
    raise exception 'Only participants';
  end if;

  -- ── Payer & recipient ──
  -- Random: pihak MALE membayar, pihak FEMALE menerima split (kebalikan
  -- dari asumsi caller=payer lama — caller match = siapa yang join kedua,
  -- murni kebetulan sisi signaling, bukan ekonomi). Private: caller bayar.
  if c.kind = 'random' then
    select gender into v_callee_gender from public.profiles where id = c.callee_id;
    if v_caller_gender = 'male' then
      v_payer := c.caller_id;
    elsif v_callee_gender = 'male' then
      v_payer := c.callee_id;
    else
      v_payer := c.caller_id; -- fallback gender tak dikenal
    end if;
    v_recipient := case when v_payer = c.caller_id then c.callee_id
                        else c.caller_id end;
  else
    v_payer := c.caller_id;
    v_recipient := c.callee_id;
  end if;

  -- ── Caller FEMALE = GRATIS (batas menit/hari) — private saja ──
  -- Random TIDAK gratis walau caller female: payer-nya tetap male.
  if c.kind is distinct from 'random' and v_caller_gender = 'female' then
    select coalesce(female_free_call_min_per_day, 30) into v_free_limit
      from app_settings where id = 'global';
    -- 2026-11-02: batas hari memakai Asia/Jakarta (bukan current_date UTC).
    select coalesce(sum(ceil(extract(epoch from
             (coalesce(cc.ended_at, now()) - cc.answered_at)) / 60)), 0)
      into v_free_used
      from public.calls cc
      join public.profiles pp on pp.id = cc.callee_id
     where cc.caller_id = me
       and cc.callee_id <> me
       and pp.gender = 'male'
       and cc.answered_at is not null
       and cc.answered_at >= v_day_start;
    if v_free_used >= v_free_limit then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
        'remaining', public.yukcoin_total(me),
        'reason', 'free_limit',
        'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
    end if;
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me),
      'free_used_min', v_free_used, 'free_limit_min', v_free_limit);
  end if;

  feat := case when c.kind = 'random' then 'call_video'
               when c.call_type = 'audio' then 'call_audio'
               else 'call_video' end;
  select case when c.kind = 'random' then call_video_cost_per_min
              when c.call_type = 'audio' then call_audio_cost_per_min
              else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);
  -- Belum dijawab → belum ada tagihan.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;
  -- Random: jangkar ke media_connected_at (di-stamp client saat ICE pertama
  -- connected) supaya "gratis 30 detik" = 30 detik call yang benar-benar
  -- tampil, bukan 30 detik sejak pair. Client lama tak men-stamp → fallback
  -- ke answered_at (perilaku sebelumnya, bukan regresi). Private tetap dari
  -- answered_at (di-set saat callee menekan Terima).
  v_anchor := case when c.kind = 'random'
                   then coalesce(c.media_connected_at, c.answered_at)
                   else c.answered_at end;
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - v_anchor)))::int);

  -- MATCH (kind='random') → gratis 30 DETIK pertama. Menit N berbayar
  -- menutup jendela [30+(N-1)*60, 30+N*60) — tagih di awal jendelanya
  -- (detik 30, 90, 150, …) supaya tak ada menit gratis terselip di ujung.
  -- Call biasa: pembulatan ke atas (detik 1–60 sudah ditagih 1 menit).
  if c.kind = 'random' then
    billable_minutes := case when elapsed_sec >= 30
                        then 1 + (elapsed_sec - 30) / 60 else 0 end;
    v_free_seconds_left := greatest(0, 30 - elapsed_sec);
  else
    billable_minutes := (elapsed_sec + 59) / 60;
  end if;

  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = v_payer and feature = feat and ref_id = p_call_id::text;
  to_bill := greatest(0, billable_minutes - already_billed);
  -- 2026-11-02: afford-check WAJIB memakai saldo PAID (topup+earned), bukan
  -- total. `charge_metered` menolak bucket `bonus`, jadi caller bonus-only
  -- yang lolos cek `yukcoin_total` akan membuat charge_metered melempar
  -- exception di tengah tick → panggilan error alih-alih berhenti halus.
  v_paid := public.yukcoin_paid_total(v_payer);
  remaining := public.yukcoin_total(me);

  -- ── Biaya KONEK (sekali per match, saat lolos 30 detik gratis) ──
  -- Female +30% dari harga konek (cut_pct dari metered_pricing.match_call).
  -- Ditagih SEBELUM menit — tak lolos grace → tak ada fee yang hangus.
  if c.kind = 'random' and elapsed_sec >= 30 then
    select coalesce((metered_pricing->'match_call'->>'unit_cost')::int, 10)
      into v_connect_cost from app_settings where id = 'global';
    select exists (
      select 1 from public.yukcoin_consumptions
       where user_id = v_payer and feature = 'match_call'
         and ref_id = p_call_id::text
    ) into v_connect_billed;
    if not v_connect_billed then
      if v_paid < v_connect_cost then
        return jsonb_build_object('ok', true, 'can_continue', false,
          'billed_minutes', already_billed,
          'charged_total', already_billed * unit_cost,
          'per_minute', unit_cost,
          'remaining', remaining, 'reason', 'insufficient',
          'free_seconds_left', 0);
      end if;
      perform public._charge_metered_core(v_payer, 'match_call',
        p_call_id::text, 1, v_recipient);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        values (v_payer, 'match_call', v_connect_cost, p_call_id::text,
                jsonb_build_object('kind', 'random', 'connect', true));
      v_connect_billed := true;
      v_paid := public.yukcoin_paid_total(v_payer);
      remaining := public.yukcoin_total(me);
    end if;
  end if;

  if to_bill > 0 then
    if v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost
          + (case when v_connect_billed then v_connect_cost else 0 end),
        'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
    end if;
    afford := v_paid / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public._charge_metered_core(v_payer, feat, p_call_id::text,
        charge_n, v_recipient,
        -- Match per-menit → tipe 'match_call' ('_income' untuk female)
        -- supaya rincian Saldo/riwayat masuk "Panggilan Match".
        case when c.kind = 'random' then 'match_call' else null end);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select v_payer, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g,
                                  'call_type', c.call_type,
                                  'kind', coalesce(c.kind, 'private'))
        from generate_series(1, charge_n) g;
      already_billed := already_billed + charge_n;
      v_paid := public.yukcoin_paid_total(v_payer);
      remaining := public.yukcoin_total(me);
    end if;
    if charge_n < to_bill or v_paid < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost
          + (case when v_connect_billed then v_connect_cost else 0 end),
        'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient',
        'free_seconds_left', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost
      + (case when v_connect_billed then v_connect_cost else 0 end),
    'per_minute', unit_cost,
    'remaining', remaining,
    'free_seconds_left', v_free_seconds_left);
end;
$function$;

-- ── 4) random_match_join — precheck male PAID >= pair + konek ──
create or replace function public.random_match_join(p_want_gender text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_want text;
  v_gender text;
  my_lat double precision;
  my_lon double precision;
  v_registered boolean;
  v_all boolean;
  v_anon boolean;
  q record;
  cid uuid;
  p_name text; p_gender text; p_age int; p_city text; p_avatar text;
  p_dist double precision;
  v_excl uuid[];
  v_payer uuid;
  v_tried uuid[] := '{}'::uuid[];
  v_points_on boolean;
  v_fee int := 2;
  v_connect int := 10;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;

  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false),
         coalesce(points_enabled, true),
         coalesce((metered_pricing->'match_call'->>'unit_cost')::int, 10)
    into v_all, v_anon, v_points_on, v_connect
    from public.app_settings where id = 'global';
  if not v_all then raise exception 'CALL_DISABLED'; end if;

  select gender, lat, lon, coalesce(is_registered, false)
    into v_gender, my_lat, my_lon, v_registered
    from public.profiles where id = me;
  if not v_anon and not v_registered then
    raise exception 'CALL_REGISTERED_ONLY';
  end if;

  -- 2026-10-31: LAWAN JENIS OTOMATIS. Male → cari female, female → cari male.
  -- Tidak ada pilihan manual "Semua".
  v_want := case v_gender
              when 'male'   then 'female'
              when 'female' then 'male'
              else coalesce(nullif(p_want_gender,''), 'all')
            end;

  if exists (
    select 1 from public.calls c
     where (c.caller_id = me or c.callee_id = me)
       and c.status in ('ringing', 'answered')
       and coalesce(c.last_seen_at, c.answered_at, c.created_at) > now() - interval '5 minutes'
  ) then
    raise exception 'ALREADY_IN_CALL';
  end if;

  -- 2026-10-31 (charge-on-match): fee dipotong SAAT pair terbentuk, bukan
  -- saat klik. Male yang jelas tak mampu bayar tidak masuk antrean.
  -- 2026-11-04: precheck memakai saldo PAID >= pair + konek — bukan total.
  -- Pair boleh didebit dari bucket bonus (_spend_yukcoin_core), tapi biaya
  -- KONEK + menit lewat charge_metered menolak bonus → male bonus-only yang
  -- lolos precheck lama dijamin call-nya mati di detik 30 (insufficient).
  if v_gender = 'male' and v_points_on
     and public.yukcoin_paid_total(me) < v_fee + v_connect then
    return jsonb_build_object('status', 'no_funds');
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  insert into public.random_match_queue
    (user_id, gender, want_gender, lat, lon, pinged_at, matched_call_id, matched_with)
  values (me, v_gender, v_want, my_lat, my_lon, now(), null, null)
  on conflict (user_id) do update
    set gender = excluded.gender,
        want_gender = excluded.want_gender,
        lat = excluded.lat,
        lon = excluded.lon,
        pinged_at = now(),
        matched_call_id = null,
        matched_with = null;

  -- Charge-on-match: loop kandidat → coba tagih pihak male → pair yang
  -- terbayar pertama yang jadi. Kandidat male yang tak mampu bayar diskip
  -- lewat precheck; spend tetap authoritative untuk race (saldo berubah
  -- antara antre dan pair). Precheck kandidat juga dinaikkan ke paid >=
  -- pair + konek dengan alasan yang sama.
  q := null;
  loop
    select rq.* into q
      from public.random_match_queue rq
     where rq.user_id <> me
       and rq.matched_call_id is null
       and rq.pinged_at > now() - interval '30 seconds'
       and (v_want = 'all' or rq.gender = v_want)
       and (rq.want_gender = 'all' or rq.want_gender = v_gender)
       and (rq.gender <> 'male' or not v_points_on
            or public.yukcoin_paid_total(rq.user_id) >= v_fee + v_connect)
       and not (rq.user_id = any (v_tried))
       and not exists (
         select 1 from public.blocks b
          where (b.blocker_id = me and b.blocked_id = rq.user_id)
             or (b.blocker_id = rq.user_id and b.blocked_id = me)
       )
       and not (rq.user_id = any (v_excl))
       and not exists (
         select 1 from public.ghost_mode_active g
          where g.user_id = rq.user_id and g.expires_at > now()
       )
       and not exists (
         select 1 from public.random_match_pairs rp
          where rp.created_at > now() - interval '10 minutes'
            and ((rp.a = me and rp.b = rq.user_id)
              or (rp.a = rq.user_id and rp.b = me))
       )
     order by
       case when my_lat is not null and rq.lat is not null
            then earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(rq.lat, rq.lon))
            else 1e12 end asc,
       rq.pinged_at asc
     for update skip locked
     limit 1;
    if not found then
      q := null;
      exit;
    end if;

    -- Payer = pihak male (female gratis). Kalau joiner female → partner
    -- male-nya yang membayar lewat fungsi internal (core, tanpa auth gate).
    v_payer := case when v_gender = 'male' then me else q.user_id end;
    begin
      perform public._spend_yukcoin_core(v_payer, 'match_search', v_fee, 'match');
      exit; -- terbayar (atau free-pass saat points_enabled OFF) → pair jadi
    exception when others then
      if v_payer = me then
        delete from public.random_match_queue where user_id = me;
        return jsonb_build_object('status', 'no_funds');
      end if;
      v_tried := v_tried || q.user_id;
      q := null;
    end;
  end loop;

  if q is null then
    return jsonb_build_object('status', 'waiting');
  end if;

  insert into public.calls
    (caller_id, callee_id, call_type, status, kind, answered_at, last_seen_at)
  values (me, q.user_id, 'video', 'answered', 'random', now(), now())
  returning id into cid;

  update public.random_match_queue
     set matched_call_id = cid, matched_with = me, pinged_at = now()
   where user_id = q.user_id;

  update public.random_match_queue
     set matched_call_id = cid, matched_with = q.user_id, pinged_at = now()
   where user_id = me;

  insert into public.random_match_pairs (a, b)
  values (least(me, q.user_id), greatest(me, q.user_id))
  on conflict do nothing;

  select p.nickname, p.gender, p.age, p.city,
         case when public.privacy_can_view(p.id, 'profile_photo', me)
              then p.avatar else '' end
    into p_name, p_gender, p_age, p_city, p_avatar
    from public.profiles p where p.id = q.user_id;

  if my_lat is not null and q.lat is not null and q.lon is not null then
    p_dist := earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(q.lat, q.lon)) / 1000.0;
  end if;

  return jsonb_build_object(
    'status', 'matched',
    'call_id', cid,
    'is_caller', true,
    'partner', jsonb_build_object(
      'uid', q.user_id,
      'nickname', coalesce(p_name, 'User'),
      'gender', coalesce(p_gender, 'other'),
      'age', p_age,
      'city', p_city,
      'avatar', coalesce(p_avatar, ''),
      'distance_km', p_dist
    )
  );
end;
$function$;
