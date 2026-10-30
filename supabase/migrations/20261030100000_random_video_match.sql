-- Random Video Call ("Match Nearby") — antrean match + riwayat (2026-10-30).
--
-- Fitur: dua user yang SAMA-SAMA menekan "Match" dipasangkan oleh server lalu
-- langsung video call TANPA ringing/konfirmasi (keputusan produk). "Next" =
-- tutup call + masuk antrean lagi. Biaya: GRATIS dulu.
--
-- Kenapa baris `calls` dibuat dengan status 'answered':
--   * Listener panggilan masuk di klien hanya bereaksi pada status 'ringing'
--     (call_service.dart) dan trigger notify_call_ringing() hanya push saat
--     'ringing' → tidak ada IncomingCallScreen / push untuk random.
--   * CallSession bisa langsung start (answered_at terisi → durasi & riwayat
--     dihitung dari situ).
--
-- Penjaga yang WAJIB (kalau tidak, fitur ini merusak alur lain):
--   1. call_history_insert() → dilewati untuk kind='random' (kalau tidak tiap
--      "Next" menulis bubble "📹 Call ended" ke private chat dengan orang
--      asing dan membuat chat baru).
--   2. call_billing_tick() → gratis untuk kind='random' (gratis dulu).
--
-- SAFE: kolom baru `calls.kind` aditif (default 'direct') + 2 tabel baru
--       (random_match_queue, random_match_pairs) + policy SELECT milik sendiri
--       pada random_match_queue. Hanya mengganti body call_history_insert &
--       call_billing_tick (bukan FROZEN; body diambil dari DB live). Fitur
--       terdampak: panggilan 1:1 (tidak berubah perilaku), riwayat call, poin
--       call, realtime panggilan masuk (random tidak memicu ringing).

-- ─────────────────────────── 1. Skema ───────────────────────────
alter table public.calls
  add column if not exists kind text not null default 'direct';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'calls_kind_check') then
    alter table public.calls
      add constraint calls_kind_check check (kind in ('direct','random'));
  end if;
end $$;

create table if not exists public.random_match_queue (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  gender          text,
  want_gender     text not null default 'all'
                  check (want_gender in ('all','male','female','other')),
  lat             double precision,
  lon             double precision,
  pinged_at       timestamptz not null default now(),
  matched_call_id uuid references public.calls(id) on delete set null,
  matched_with    uuid references public.profiles(id) on delete set null
);

create index if not exists random_match_queue_waiting
  on public.random_match_queue (pinged_at desc)
  where matched_call_id is null;

create table if not exists public.random_match_pairs (
  a          uuid not null references public.profiles(id) on delete cascade,
  b          uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b)
);

alter table public.random_match_queue enable row level security;
alter table public.random_match_pairs enable row level security;

-- SAFE: user hanya membaca baris antreannya sendiri (dipakai realtime penunggu); tulis hanya lewat RPC security definer. Fitur terdampak: random video match.
drop policy if exists random_match_queue_select_own on public.random_match_queue; -- SAFE: policy milik tabel baru random_match_queue, dibuat ulang idempoten; tidak menyentuh tabel bersama.
create policy random_match_queue_select_own on public.random_match_queue -- SAFE: SELECT baris sendiri saja pada tabel baru random_match_queue; RLS tabel bersama tidak disentuh.
  for select using (user_id = auth.uid());

-- Realtime: penunggu mendengar UPDATE barisnya sendiri (matched_call_id).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'random_match_queue'
  ) then
    alter publication supabase_realtime add table public.random_match_queue;
  end if;
end $$;

-- ─────────────────── 2. Antrean: join / ping / leave ───────────────────
create or replace function public.random_match_join(p_want_gender text default 'all')
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  me uuid := auth.uid();
  v_want text := coalesce(nullif(p_want_gender, ''), 'all');
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
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;

  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false)
    into v_all, v_anon from public.app_settings where id = 'global';
  if not v_all then raise exception 'CALL_DISABLED'; end if;

  select gender, lat, lon, coalesce(is_registered, false)
    into v_gender, my_lat, my_lon, v_registered
    from public.profiles where id = me;
  if not v_anon and not v_registered then
    raise exception 'CALL_REGISTERED_ONLY';
  end if;

  -- Jangan ikut antrean saat sedang dalam panggilan lain.
  if exists (
    select 1 from public.calls c
     where (c.caller_id = me or c.callee_id = me)
       and c.status in ('ringing', 'answered')
       and coalesce(c.last_seen_at, c.answered_at, c.created_at) > now() - interval '5 minutes'
  ) then
    raise exception 'ALREADY_IN_CALL';
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

  -- Cari pasangan yang juga sedang menunggu. Gender harus cocok DUA arah.
  select rq.* into q
    from public.random_match_queue rq
   where rq.user_id <> me
     and rq.matched_call_id is null
     and rq.pinged_at > now() - interval '30 seconds'
     and (v_want = 'all' or rq.gender = v_want)
     and (rq.want_gender = 'all' or rq.want_gender = v_gender)
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
    return jsonb_build_object('status', 'waiting');
  end if;

  insert into public.calls
    (caller_id, callee_id, call_type, status, kind, answered_at, last_seen_at)
  values (me, q.user_id, 'video', 'answered', 'random', now(), now())
  returning id into cid;

  update public.random_match_queue
     set matched_call_id = cid, matched_with = q.user_id, pinged_at = now()
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

create or replace function public.random_match_ping()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  me uuid := auth.uid();
  row_q record;
  p_name text; p_gender text; p_age int; p_city text; p_avatar text;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select * into row_q from public.random_match_queue where user_id = me;
  if not found then
    return jsonb_build_object('status', 'idle');
  end if;

  -- Sudah dipasangkan orang lain (jalur realtime bisa telat/hilang).
  if row_q.matched_call_id is not null then
    select p.nickname, p.gender, p.age, p.city,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end
      into p_name, p_gender, p_age, p_city, p_avatar
      from public.profiles p where p.id = row_q.matched_with;
    return jsonb_build_object(
      'status', 'matched',
      'call_id', row_q.matched_call_id,
      'is_caller', (select caller_id = me from public.calls where id = row_q.matched_call_id),
      'partner', jsonb_build_object(
        'uid', row_q.matched_with,
        'nickname', coalesce(p_name, 'User'),
        'gender', coalesce(p_gender, 'other'),
        'age', p_age,
        'city', p_city,
        'avatar', coalesce(p_avatar, ''),
        'distance_km', null
      )
    );
  end if;

  update public.random_match_queue set pinged_at = now() where user_id = me;
  return jsonb_build_object('status', 'waiting');
end;
$function$;

create or replace function public.random_match_leave()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  delete from public.random_match_queue where user_id = me;
  return jsonb_build_object('ok', true);
end;
$function$;

-- ─────────────────── 3. Data radar & riwayat ───────────────────
create or replace function public.random_match_stats()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  v_waiting int;
  v_online int;
  v_sample jsonb;
  v_excl uuid[];
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select lat, lon into my_lat, my_lon from public.profiles where id = me;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl from public.admin_excluded_uids() ae;

  select count(*) into v_waiting
    from public.random_match_queue q
   where q.matched_call_id is null and q.pinged_at > now() - interval '30 seconds';

  select count(*) into v_online
    from public.profiles p
   where p.id <> me
     and p.status in ('online', 'idle')
     and p.last_seen >= now() - interval '30 minutes'
     and not (p.id = any (v_excl))
     and not exists (select 1 from public.ghost_mode_active g
                      where g.user_id = p.id and g.expires_at > now());

  select coalesce(jsonb_agg(x order by x->>'distance_km' nulls last), '[]'::jsonb)
    into v_sample
    from (
      select jsonb_build_object(
               'uid', p.id,
               'nickname', p.nickname,
               'gender', p.gender,
               'avatar', case when public.privacy_can_view(p.id, 'profile_photo', me)
                              then p.avatar else '' end,
               'city', p.city,
               'distance_km', case when my_lat is not null and p.lat is not null and p.lon is not null
                                   then round((earth_distance(ll_to_earth(my_lat, my_lon),
                                                              ll_to_earth(p.lat, p.lon)) / 1000.0)::numeric, 1)
                                   else null end
             ) as x
        from public.profiles p
       where p.id <> me
         and p.status in ('online', 'idle')
         and p.last_seen >= now() - interval '30 minutes'
         and public.privacy_can_view(p.id, 'presence', me)
         and not (p.id = any (v_excl))
         and not exists (select 1 from public.ghost_mode_active g
                          where g.user_id = p.id and g.expires_at > now())
         and not exists (select 1 from public.blocks b
                          where (b.blocker_id = me and b.blocked_id = p.id)
                             or (b.blocker_id = p.id and b.blocked_id = me))
       order by p.last_seen desc
       limit 8
    ) s;

  return jsonb_build_object('waiting', v_waiting, 'online', v_online, 'sample', v_sample);
end;
$function$;

create or replace function public.random_call_history(
  p_limit integer default 30,
  p_offset integer default 0
)
returns table(
  call_id uuid,
  partner_id uuid,
  partner_name text,
  partner_avatar text,
  partner_gender text,
  partner_age integer,
  partner_city text,
  started_at timestamptz,
  ended_at timestamptz,
  duration_sec integer,
  online boolean,
  status text
)
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  me uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 30), 100));
  off int := greatest(0, coalesce(p_offset, 0));
begin
  if me is null then raise exception 'Not authenticated'; end if;

  return query
  select c.id,
         other.id,
         coalesce(nullif(other.nickname, ''), 'User'),
         case when public.privacy_can_view(other.id, 'profile_photo', me)
              then coalesce(other.avatar, '') else '' end,
         coalesce(other.gender, 'other'),
         other.age,
         other.city,
         coalesce(c.answered_at, c.created_at),
         c.ended_at,
         greatest(0, extract(epoch from
           (coalesce(c.ended_at, now()) - coalesce(c.answered_at, c.created_at)))::int),
         (other.status in ('online', 'idle') and other.last_seen >= now() - interval '30 minutes'),
         c.status
    from public.calls c
    join public.profiles other
      on other.id = case when c.caller_id = me then c.callee_id else c.caller_id end
   where c.kind = 'random'
     and (c.caller_id = me or c.callee_id = me)
     and c.status <> 'ringing'
   order by coalesce(c.ended_at, c.created_at) desc
   limit lim offset off;
end;
$function$;

-- ─────────────────── 4. Pembersihan (cron tiap menit) ───────────────────
create or replace function public.random_match_sweep()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
declare v_q int; v_c int; v_p int;
begin
  delete from public.random_match_queue
   where matched_call_id is null
     and pinged_at < now() - interval '60 seconds';
  get diagnostics v_q = row_count;

  -- Call random yang ditinggal (app mati / crash) ditutup supaya riwayat benar
  -- dan tidak menahan user dianggap "sedang call".
  update public.calls
     set status = 'ended', ended_at = now()
   where kind = 'random' and status = 'answered'
     and coalesce(last_seen_at, answered_at, created_at) < now() - interval '3 minutes';
  get diagnostics v_c = row_count;

  delete from public.random_match_pairs where created_at < now() - interval '1 day';
  get diagnostics v_p = row_count;

  return jsonb_build_object('queue', v_q, 'calls', v_c, 'pairs', v_p);
end;
$function$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'random-match-sweep';
    perform cron.schedule('random-match-sweep', '* * * * *',
                          'select public.random_match_sweep()');
  end if;
end $$;

-- ─────────────────── 5. Flag fitur (admin dulu) ───────────────────
update public.app_settings
   set feature_flags = coalesce(feature_flags, '{}'::jsonb)
                       || jsonb_build_object('random_call', jsonb_build_object('published', false))
 where id = 'global'
   and not (coalesce(feature_flags, '{}'::jsonb) ? 'random_call');

-- ─────────────────── 6. Grant ───────────────────
revoke execute on function public.random_match_join(text) from public, anon;
revoke execute on function public.random_match_ping() from public, anon;
revoke execute on function public.random_match_leave() from public, anon;
revoke execute on function public.random_match_stats() from public, anon;
revoke execute on function public.random_call_history(integer, integer) from public, anon;
revoke execute on function public.random_match_sweep() from public, anon, authenticated;

grant execute on function public.random_match_join(text) to authenticated, service_role; -- SAFE: grant rutin RPC klien (antrean match) untuk role login.
grant execute on function public.random_match_ping() to authenticated, service_role; -- SAFE: grant rutin RPC klien (heartbeat antrean).
grant execute on function public.random_match_leave() to authenticated, service_role; -- SAFE: grant rutin RPC klien (keluar antrean).
grant execute on function public.random_match_stats() to authenticated, service_role; -- SAFE: grant rutin RPC klien (data radar).
grant execute on function public.random_call_history(integer, integer) to authenticated, service_role; -- SAFE: grant rutin RPC klien (riwayat random call).
grant execute on function public.random_match_sweep() to service_role; -- SAFE: hanya cron/service_role yang membersihkan antrean basi.

-- ─────────────────── 7. Penjaga alur lain (body dari DB live) ───────────────────
CREATE OR REPLACE FUNCTION public.call_history_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cid text;
  cname text;
  cgender text;
  dur int;
  stext text;
  txt text;
  exists_cnt int;
begin
  if new.status not in ('ended','failed','canceled','declined','missed','busy') then return new; end if;
  if old.status = new.status then return new; end if;
  -- Random video call: TIDAK menulis bubble "Call ended" ke private chat
  -- (tidak ada chat yang disepakati dengan orang asing; tiap "Next" akan
  -- membuat chat baru). Riwayatnya dibaca lewat random_call_history().
  if new.kind = 'random' then return new; end if;

  select case when new.caller_id::text < new.callee_id::text
         then new.caller_id::text || '_' || new.callee_id::text
         else new.callee_id::text || '_' || new.caller_id::text end into cid;

  select nickname, gender into cname, cgender from public.profiles where id = new.caller_id;
  if cname is null or cname = '' then cname := 'User'; end if;
  if cgender is null then cgender := 'other'; end if;

  if new.answered_at is not null and new.ended_at is not null then
    dur := extract(epoch from (new.ended_at - new.answered_at))::int;
  else
    dur := 0;
  end if;
  if dur < 0 then dur := 0; end if;

  if new.status in ('ended','failed') and dur > 0 then
    stext := 'Call ended (' || (dur/60)::int || ':' || lpad((dur%60)::text,2,'0') || ')';
  elsif new.status in ('ended','failed') then
    stext := 'Call ended';
  elsif new.status = 'canceled' then
    stext := 'Call canceled';
  elsif new.status = 'declined' then
    stext := 'Call declined';
  elsif new.status = 'busy' then
    stext := 'Busy';
  else
    stext := 'Missed call';
  end if;

  if new.call_type = 'video' then
    txt := '📹 ' || stext;
  else
    txt := '📞 ' || stext;
  end if;

  -- Dedup kuat: pesan call dengan teks sama di chat sama dalam 30 detik
  select count(*) into exists_cnt from public.private_messages
   where chat_id = cid and type='call' and text = txt
     and created_at > now() - interval '30 seconds';
  if exists_cnt > 0 then return new; end if;

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
  values (cid, new.caller_id, cname, cgender, txt, 'call', '');

  return new;
exception when others then return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.call_billing_tick(p_call_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  c record;
  feat text; unit_cost int; cut_pct int;
  elapsed_sec int; billable_minutes int; already_billed int; to_bill int;
  afford int; charge_n int;
  remaining int;
  points_on boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  -- Master toggle koin (admin "Sistem poin") PALING ATAS — jalur OFF
  -- tak menyentuh config/billing, call gratis total.
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false then
    return jsonb_build_object(
      'ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  -- Gerbang fitur publish — jalur OFF tak menyentuh config/billing.
  if not public.feature_enabled_for('call_billing') then
    return jsonb_build_object(
      'ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  select * into c from public.calls where id = p_call_id;
  if not found then raise exception 'Call not found'; end if;
  if c.caller_id <> me then raise exception 'Only caller can be billed'; end if;

  -- Random video call: GRATIS dulu (keputusan produk 2026-10-30). Tarif bisa
  -- diaktifkan nanti lewat app_settings.random_call_cost_per_min.
  if c.kind = 'random' then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  feat := case c.call_type when 'audio' then 'call_audio' else 'call_video' end;
  select case c.call_type
           when 'audio' then call_audio_cost_per_min
           else call_video_cost_per_min end
    into unit_cost
    from app_settings where id = 'global';
  unit_cost := coalesce(unit_cost, 0);
  cut_pct := coalesce((select call_cut_pct from app_settings where id='global'), 70);

  -- Belum dijawab → belum ada tagihan.
  if c.answered_at is null then
    return jsonb_build_object('ok', true, 'can_continue', true,
      'billed_minutes', 0, 'charged_total', 0, 'per_minute', unit_cost,
      'remaining', public.yukcoin_total(me));
  end if;

  -- Detik berjalan SERVER-SIDE dari answered_at (anti-tamper client).
  elapsed_sec := greatest(0, floor(extract(epoch from (now() - c.answered_at)))::int);

  -- Menit berbayar = ceil(elapsed / 60). Menit pertama tetap ditagih penuh
  -- saat detik 1..60 (pembulatan ke atas) → tidak ada celah gratis.
  billable_minutes := (elapsed_sec + 59) / 60;

  -- Sudah ditagih berapa menit untuk call ini (idempoten).
  select count(*) into already_billed
    from public.yukcoin_consumptions
    where user_id = me and feature = feat and ref_id = p_call_id::text;

  to_bill := greatest(0, billable_minutes - already_billed);
  remaining := public.yukcoin_total(me);

  if to_bill > 0 then
    if remaining < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient');
    end if;

    -- Tagih sebanyak yang sanggup (afford-guard → saldo tak pernah minus).
    afford := remaining / greatest(unit_cost, 1);
    charge_n := least(to_bill, afford);
    if charge_n > 0 then
      perform public.charge_metered(me, feat, p_call_id::text, charge_n, c.callee_id);
      insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
        select me, feat, unit_cost, p_call_id::text,
               jsonb_build_object('minute', already_billed + g, 'call_type', c.call_type)
        from generate_series(1, charge_n) g;
      already_billed := already_billed + charge_n;
      remaining := public.yukcoin_total(me);
    end if;

    if charge_n < to_bill or remaining < unit_cost then
      return jsonb_build_object('ok', true, 'can_continue', false,
        'billed_minutes', already_billed,
        'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
        'remaining', remaining, 'reason', 'insufficient');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'can_continue', true,
    'billed_minutes', already_billed,
    'charged_total', already_billed * unit_cost, 'per_minute', unit_cost,
    'remaining', remaining);
end; $function$;