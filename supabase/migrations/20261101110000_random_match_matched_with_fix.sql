-- Fix random_match_join: baris PARTNER di antrean di-set
-- `matched_with = q.user_id` (uid-nya SENDIRI) — seharusnya `me` (uid joiner).
-- Akibat: sisi yang menunggu membaca matched_with = dirinya sendiri →
-- random_match_ping mengembalikan profil SENDIRI sebagai "partner" →
-- nama di layar call match tampil nama sendiri (kedua HP tampil nama sama)
-- dan otherUid untuk buka chat setelah call ikut salah.
-- Baris joiner sudah benar; hanya baris partner yang dikoreksi.
-- menyentuh: random_match_join
create or replace function public.random_match_join(p_want_gender text default 'all')
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
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
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.feature_enabled_for('random_call') then
    raise exception 'FEATURE_DISABLED';
  end if;

  select coalesce(call_all_enabled, true), coalesce(call_anon_enabled, false),
         coalesce(points_enabled, true)
    into v_all, v_anon, v_points_on
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
  if v_gender = 'male' and v_points_on
     and public.yukcoin_total(me) < v_fee then
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
  -- antara antre dan pair).
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
            or public.yukcoin_total(rq.user_id) >= v_fee)
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
