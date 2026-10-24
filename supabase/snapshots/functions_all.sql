-- SNAPSHOT SEMUA fungsi public (auto-generate). JANGAN edit manual.
-- Regenerate: scripts/snapshot_functions.sh --all
-- Timestamp: 2026-10-24T15:51:34Z

-- snapshot-fn: _anon_gate_insert
CREATE OR REPLACE FUNCTION public._anon_gate_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  return new;
end;
$function$

-- snapshot-fn: _anon_write_ok
CREATE OR REPLACE FUNCTION public._anon_write_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    not coalesce(
      (select require_registration from public.app_settings where id = 'global'),
      false)
  or auth.uid() in (select du from public.admin_dummy_uids() du)
  or coalesce(auth.email(), '') = 'zunixe@gmail.com'
  -- User punya email di auth (registered/Google/OTP) → boleh menulis
  -- profilnya sendiri (dibuat saat isi nama via registerProfile).
  or coalesce(auth.email(), '') <> ''
  or coalesce((select is_registered from public.profiles where id = auth.uid()), false),
  false)
$function$

-- snapshot-fn: _are_friends
CREATE OR REPLACE FUNCTION public._are_friends(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.friend_requests fr
    where fr.status = 'accepted'
      and ((fr.from_id = a and fr.to_id = b)
        or (fr.from_id = b and fr.to_id = a))
  )
$function$

-- snapshot-fn: _email_is_admin
CREATE OR REPLACE FUNCTION public._email_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(auth.email(), '') = 'zunixe@gmail.com'
$function$

-- snapshot-fn: _privacy_are_friends
CREATE OR REPLACE FUNCTION public._privacy_are_friends(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.follows f1
    join public.follows f2
      on f1.followee_id = f2.follower_id
     and f1.follower_id = f2.followee_id
    where f1.follower_id = a
      and f1.followee_id = b
  );
$function$

-- snapshot-fn: _social_registered_guard
CREATE OR REPLACE FUNCTION public._social_registered_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_a uuid;
  v_b uuid;
begin
  if tg_table_name = 'friend_requests' then
    v_a := new.from_id;
    v_b := new.to_id;
  else
    v_a := new.follower_id;
    v_b := new.followee_id;
  end if;

  if exists (
    select 1 from public.profiles p
    where p.id in (v_a, v_b)
      and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
  end if;
  return new;
end;
$function$

-- snapshot-fn: _viewer_is_registered
CREATE OR REPLACE FUNCTION public._viewer_is_registered()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce((select is_registered from public.profiles where id = auth.uid()), false)
$function$

-- snapshot-fn: activity_leaderboard
CREATE OR REPLACE FUNCTION public.activity_leaderboard(p_scope text DEFAULT 'weekly'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  me jsonb;
  v_excl uuid[];
  v_dummy uuid[];
  v_lim int;
  v_off int;
  v_since timestamptz;
  v_me uuid := auth.uid();
begin
  v_lim := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_off := greatest(coalesce(p_offset, 0), 0);
  v_since := case when p_scope = 'alltime' then null
                  else (now() - interval '7 days') end;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  with raw as (
    select p.author_id as uid, count(*)::int as posts, 0::int as stories, 0::int as priv, 0::int as room
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    select s.author_id, 0, count(*)::int, 0, 0
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    select m.sender_id, 0, 0, count(*)::int, 0
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, 0, 0, 0, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
  ),
  agg as (
    select uid,
           sum(posts)::int as posts,
           sum(stories)::int as stories,
           sum(priv)::int as priv,
           sum(room)::int as room,
           (sum(posts) + sum(stories) + sum(priv) + sum(room))::int as score
      from raw
     group by uid
  ),
  final as (
    select
      p.id, p.nickname, p.avatar, p.country, p.is_registered, p.gender,
      p.followers_count, p.friends_count,
      a.posts, a.stories, a.priv, a.room, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
      -- Hormati privasi Top Aktif (nobody/friends/only/kecuali).
      and public.privacy_can_view(p.id, 'leaderboard', v_me)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', f.rank,
      'uid', f.id,
      'nickname', f.nickname,
      'avatar', f.avatar,
      'country', f.country,
      'gender', f.gender,
      'is_registered', f.is_registered,
      'score', f.score,
      'post_count', f.posts,
      'story_count', f.stories,
      'msg_private', f.priv,
      'msg_room', f.room,
      'followers_count', coalesce(f.followers_count,0),
      'friends_count', coalesce(f.friends_count,0)
    ) order by f.rank), '[]'::jsonb)
    into result
    from final f
   where f.rank > v_off and f.rank <= v_off + v_lim;

  with raw as (
    select p.author_id as uid, count(*)::int s
      from public.posts p
     where p.author_id is not null and (v_since is null or p.created_at >= v_since)
     group by p.author_id
    union all
    select s.author_id, count(*)::int
      from public.stories s
     where s.author_id is not null and (v_since is null or s.created_at >= v_since)
     group by s.author_id
    union all
    select m.sender_id, count(*)::int
      from public.private_messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
    union all
    select m.sender_id, count(*)::int
      from public.messages m
     where m.sender_id is not null and (v_since is null or m.created_at >= v_since)
     group by m.sender_id
  ),
  agg as ( select uid, sum(s)::int as score from raw group by uid ),
  final as (
    select p.id, a.score,
      row_number() over (order by a.score desc, p.created_at asc) as rank
    from agg a
    join public.profiles p on p.id = a.uid
    where a.score > 0
      and p.status <> 'invisible'
      and (p.is_registered = true or p.status <> 'offline')
      and not (p.id = any(v_excl))
      and not (p.id = any(v_dummy))
      and public.privacy_can_view(p.id, 'leaderboard', v_me)
  )
  select jsonb_build_object('rank', f.rank, 'score', f.score)
    into me
    from final f
   where f.id = v_me;

  return jsonb_build_object('scope', p_scope, 'entries', result, 'me', me);
end;
$function$

-- snapshot-fn: add_post_comment
CREATE OR REPLACE FUNCTION public.add_post_comment(p_post_id uuid, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); my_name text; new_id bigint;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) = 0 or length(p_text) > 500 then
    raise exception 'Invalid comment';
  end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'Post not found';
  end if;
  select nickname into my_name from public.profiles where id = me;
  insert into public.post_comments (post_id, author_id, author_name, text)
    values (p_post_id, me, coalesce(my_name,'Anon'), p_text)
    returning id into new_id;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $function$

-- snapshot-fn: admin_active_calls
CREATE OR REPLACE FUNCTION public.admin_active_calls()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when coalesce(auth.jwt() ->> 'email', '') <> 'zunixe@gmail.com'
      then '[]'::jsonb
    else coalesce((
      select jsonb_agg(t order by t.created_at desc)
      from (
        select
          c.id::text as id,
          case when c.caller_id::text < c.callee_id::text
            then c.caller_id::text || '_' || c.callee_id::text
            else c.callee_id::text || '_' || c.caller_id::text
          end as chat_id,
          c.caller_id::text as caller_id,
          c.callee_id::text as callee_id,
          coalesce(pc.nickname, 'Unknown') as caller_name,
          coalesce(pd.nickname, 'Unknown') as callee_name,
          c.call_type,
          c.status,
          c.created_at,
          c.answered_at
        from public.calls c
        left join public.profiles pc on pc.id = c.caller_id
        left join public.profiles pd on pd.id = c.callee_id
        where (c.status = 'answered' and c.ended_at is null)
           or (c.status = 'ringing' and c.created_at > now() - interval '60 seconds')
      ) t
    ), '[]'::jsonb)
  end;
$function$

-- snapshot-fn: admin_ai_autoschedule
CREATE OR REPLACE FUNCTION public.admin_ai_autoschedule(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_hours jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts d where d.uid = p_uid) then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(hr order by hr), '[]'::jsonb)
  into v_hours
  from (
    select extract(hour from (m.created_at + interval '7 hours'))::int as hr
    from public.private_messages m
    where m.sender_id = p_uid
      and m.created_at > now() - interval '14 days'
      and coalesce(m.type, 'text') = 'text'
    group by hr
    having count(*) >= 2
  ) s;

  -- Fallback: kebiasaan kosong/minim → pakai jam aktif generik 8-23.
  if v_hours is null or jsonb_array_length(v_hours) < 6 then
    v_hours := '[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]'::jsonb;
  end if;

  update public.dummy_accounts
     set ai_active_hours = v_hours
   where uid = p_uid;

  return jsonb_build_object('hours', v_hours);
end;
$function$

-- snapshot-fn: admin_ai_provider_activate
CREATE OR REPLACE FUNCTION public.admin_ai_provider_activate(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.ai_provider_config where id = p_id) then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;
  update public.ai_provider_config set is_active = false where is_active = true;
  update public.ai_provider_config set is_active = true, updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$function$

-- snapshot-fn: admin_ai_provider_delete
CREATE OR REPLACE FUNCTION public.admin_ai_provider_delete(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_active boolean;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select p.is_active into v_active
  from public.ai_provider_config p where p.id = p_id;
  if v_active is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;
  if v_active then
    raise exception 'PROVIDER_ACTIVE';
  end if;
  delete from public.ai_provider_config where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$function$

-- snapshot-fn: admin_ai_provider_list
CREATE OR REPLACE FUNCTION public.admin_ai_provider_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'label', p.label,
      'api_base', coalesce(p.api_base, ''),
      'api_key', coalesce(p.api_key, ''),
      'default_model', coalesce(p.default_model, ''),
      'story_model', coalesce(p.story_model, ''),
      'fallback_model', coalesce(p.fallback_model, ''),
      'is_active', p.is_active,
      'updated_at', p.updated_at
    ) order by p.is_active desc, p.updated_at desc)
    from public.ai_provider_config p
  ), '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_ai_provider_save
CREATE OR REPLACE FUNCTION public.admin_ai_provider_save(p_id text DEFAULT NULL::text, p_label text DEFAULT NULL::text, p_api_base text DEFAULT NULL::text, p_api_key text DEFAULT NULL::text, p_default_model text DEFAULT NULL::text, p_story_model text DEFAULT NULL::text, p_fallback_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_id text;
  v_slug text;
  v_label text;
  v_row public.ai_provider_config;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  v_id := btrim(coalesce(p_id, ''));
  if v_id = '' then v_id := null; end if;
  v_label := btrim(coalesce(p_label, ''));
  if v_label = '' then v_label := null; end if;

  if v_id is null then
    v_slug := lower(regexp_replace(coalesce(p_label, ''), '[^a-z0-9]+', '-', 'gi'));
    v_slug := btrim(v_slug, '-');
    if v_slug is null or v_slug = '' then v_slug := 'provider'; end if;
    v_id := v_slug;
    if exists (select 1 from public.ai_provider_config where id = v_id) then
      v_id := v_slug || '-' || substr(md5(clock_timestamp()::text), 1, 6);
    end if;
    v_label := btrim(coalesce(p_label, ''));
    if v_label = '' then v_label := null; end if;
    if v_label is null then v_label := v_id; end if;
    insert into public.ai_provider_config
      (id, label, api_base, api_key, default_model, story_model, fallback_model, is_active)
    values (v_id, v_label,
            coalesce(p_api_base, ''), coalesce(p_api_key, ''),
            coalesce(p_default_model, ''), coalesce(p_story_model, ''),
            coalesce(p_fallback_model, ''), false)
    returning * into v_row;
  else
    if v_label is null then
      select p.label into v_label
      from public.ai_provider_config p where p.id = v_id;
    end if;
    update public.ai_provider_config
    set label = coalesce(v_label, label),
        api_base = coalesce(p_api_base, api_base),
        api_key = coalesce(p_api_key, api_key),
        default_model = coalesce(p_default_model, default_model),
        story_model = coalesce(p_story_model, story_model),
        fallback_model = coalesce(p_fallback_model, fallback_model),
        updated_at = now()
    where id = v_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'PROVIDER_NOT_FOUND';
    end if;
  end if;

  return jsonb_build_object(
    'id', v_row.id, 'label', v_row.label,
    'api_base', coalesce(v_row.api_base, ''),
    'api_key', coalesce(v_row.api_key, ''),
    'default_model', coalesce(v_row.default_model, ''),
    'story_model', coalesce(v_row.story_model, ''),
    'fallback_model', coalesce(v_row.fallback_model, ''),
    'is_active', v_row.is_active
  );
end;
$function$

-- snapshot-fn: admin_ai_settings
CREATE OR REPLACE FUNCTION public.admin_ai_settings(p_global_enabled boolean DEFAULT NULL::boolean, p_max_replies integer DEFAULT NULL::integer, p_min_interval integer DEFAULT NULL::integer, p_guard_enabled boolean DEFAULT NULL::boolean, p_api_base text DEFAULT NULL::text, p_api_key text DEFAULT NULL::text, p_default_model text DEFAULT NULL::text, p_stt_base text DEFAULT NULL::text, p_stt_key text DEFAULT NULL::text, p_ai_ai_enabled boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_row public.app_settings;
  v_prov public.ai_provider_config;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  insert into public.app_settings (id) values ('global')
  on conflict (id) do nothing;

  update public.app_settings
  set ai_global_enabled = coalesce(p_global_enabled, ai_global_enabled),
      ai_max_replies_per_hour = coalesce(p_max_replies, ai_max_replies_per_hour),
      ai_min_interval_sec = coalesce(p_min_interval, ai_min_interval_sec),
      ai_guard_enabled = coalesce(p_guard_enabled, ai_guard_enabled),
      ai_ai_chat_enabled = coalesce(p_ai_ai_enabled, ai_ai_chat_enabled),
      updated_at = now()
  where id = 'global'
  returning * into v_row;

  -- Hanya pastikan baris provider bila ada field provider yang ditulis.
  -- Tanpa ini, baris 'global' yang sengaja dihapus user bangkit lagi
  -- di setiap pembacaan (GET tanpa parameter).
  if p_api_base is not null
     or p_api_key is not null
     or p_default_model is not null
     or p_stt_base is not null
     or p_stt_key is not null then
    insert into public.ai_provider_config (id) values ('global')
    on conflict (id) do nothing;
  end if;

  update public.ai_provider_config
  set api_base = coalesce(p_api_base, api_base),
      api_key = coalesce(p_api_key, api_key),
      default_model = coalesce(p_default_model, default_model),
      stt_api_base = coalesce(p_stt_base, stt_api_base),
      stt_api_key = coalesce(p_stt_key, stt_api_key),
      updated_at = now()
  where id = 'global'
  returning * into v_prov;

  return jsonb_build_object(
    'ai_global_enabled', v_row.ai_global_enabled,
    'ai_max_replies_per_hour', v_row.ai_max_replies_per_hour,
    'ai_min_interval_sec', v_row.ai_min_interval_sec,
    'ai_guard_enabled', v_row.ai_guard_enabled,
    'ai_ai_chat_enabled', v_row.ai_ai_chat_enabled,
    'ai_api_base', v_prov.api_base,
    'ai_api_key', v_prov.api_key,
    'ai_default_model', v_prov.default_model,
    'ai_stt_base', v_prov.stt_api_base,
    'ai_stt_key', v_prov.stt_api_key
  );
end;
$function$

-- snapshot-fn: admin_attribution_summary
CREATE OR REPLACE FUNCTION public.admin_attribution_summary(p_days integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_since timestamptz;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  v_since := case when p_days > 0 then now() - (p_days || ' days')::interval else null end;

  select jsonb_build_object(
    'total', (select count(*) from public.user_devices d
              where (v_since is null or d.attribution_at >= v_since)),
    'sources', coalesce((
      select jsonb_agg(row_to_json(t) order by t.users desc)
      from (
        select
          coalesce(nullif(d.attribution_source,''), 'unknown') as source,
          count(*)::int as users,
          count(distinct d.user_id)::int as unique_users
        from public.user_devices d
        where (v_since is null or d.attribution_at >= v_since)
        group by 1
      ) t
    ), '[]'::jsonb),
    'campaigns', coalesce((
      select jsonb_agg(row_to_json(c) order by c.users desc)
      from (
        select
          coalesce(nullif(d.utm_campaign,''), '(tanpa kampanye)') as campaign,
          coalesce(nullif(d.attribution_source,''), 'unknown') as source,
          count(*)::int as users
        from public.user_devices d
        where (v_since is null or d.attribution_at >= v_since)
          and nullif(d.utm_campaign,'') is not null
        group by 1, 2
        limit 30
      ) c
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_attribution_users_page
CREATE OR REPLACE FUNCTION public.admin_attribution_users_page(p_source text DEFAULT ''::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'total', (
      select count(*) from public.user_devices d
      where nullif(p_source,'') is null
         or coalesce(nullif(d.attribution_source,''), 'unknown') = p_source
    ),
    'items', coalesce((
      select jsonb_agg(row_to_json(x) order by x.attribution_at desc nulls last)
      from (
        select
          d.user_id,
          p.nickname,
          p.email,
          p.city,
          p.country,
          p.is_registered,
          coalesce(nullif(d.attribution_source,''), 'unknown') as source,
          d.utm_source,
          d.utm_medium,
          d.utm_campaign,
          d.referrer_raw,
          d.brand,
          d.model,
          d.attribution_at,
          d.created_at
        from public.user_devices d
        left join public.profiles p on p.id = d.user_id
        where nullif(p_source,'') is null
           or coalesce(nullif(d.attribution_source,''), 'unknown') = p_source
        order by d.attribution_at desc nulls last
        limit greatest(p_limit, 1) offset greatest(p_offset, 0)
      ) x
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_city_stats
CREATE OR REPLACE FUNCTION public.admin_city_stats(p_country text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  v_country text := coalesce(nullif(btrim(coalesce(p_country, '')), ''), 'Tidak diketahui');
  res jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select coalesce(jsonb_agg(t order by t.count desc, t.city), '[]'::jsonb)
    into res
  from (
    select
      coalesce(nullif(btrim(city), ''), 'Tidak diketahui') as city,
      count(*) as count,
      count(*) filter (where is_registered) as registered
    from public.profiles
    where coalesce(nullif(btrim(country), ''), 'Tidak diketahui') = v_country
      and not (id = any(v_excl))
      and not (id = any(v_dummy))
      and coalesce(needs_onboarding, false) = false
    group by 1
  ) t;

  return coalesce(res, '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_contact_delete
CREATE OR REPLACE FUNCTION public.admin_contact_delete(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  delete from public.contact_messages where id = p_id;
end;
$function$

-- snapshot-fn: admin_contact_messages_page
CREATE OR REPLACE FUNCTION public.admin_contact_messages_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.contact_messages),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'created_at', m.created_at,
        'name', m.name,
        'message', m.message,
        'user_id', m.user_id,
        'is_read', m.is_read,
        -- Identitas pengirim dari profil (bila login). nickname fallback ke
        -- 'Anon' (default kolom), avatar = path/base64 (UI resolve sendiri).
        'nickname', p.nickname,
        'avatar', p.avatar
      ) order by m.created_at desc
    ), '[]'::jsonb)
  )
  into result
  from (
    select * from public.contact_messages
    order by created_at desc
    limit p_limit offset p_offset
  ) m
  left join public.profiles p on p.id = m.user_id;

  return result;
end;
$function$

-- snapshot-fn: admin_contact_set_read
CREATE OR REPLACE FUNCTION public.admin_contact_set_read(p_id uuid, p_read boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update public.contact_messages set is_read = p_read where id = p_id;
end;
$function$

-- snapshot-fn: admin_country_stats
CREATE OR REPLACE FUNCTION public.admin_country_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  res jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select coalesce(jsonb_agg(t order by t.count desc, t.country), '[]'::jsonb)
    into res
  from (
    select
      coalesce(nullif(btrim(country), ''), 'Tidak diketahui') as country,
      count(*) as count,
      count(*) filter (where is_registered) as registered
    from public.profiles
    where not (id = any(v_excl))
      and not (id = any(v_dummy))
      and coalesce(needs_onboarding, false) = false
    group by 1
  ) t;

  return coalesce(res, '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_cron_health
CREATE OR REPLACE FUNCTION public.admin_cron_health(p_lookback_hours integer DEFAULT 168)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'unack_count', (
      select count(*) from public.admin_alerts where acknowledged_at is null
    ),
    'jobs', coalesce((
      select jsonb_agg(x.obj order by x.fails desc)
      from (
        select jsonb_build_object(
                 'jobid', j.jobid,
                 'name', left(regexp_replace(j.command, '\s+', ' ', 'g'), 120),
                 'fails', count(*) filter (where jrd.status = 'failed'),
                 'runs', count(*),
                 'last_status', (array_agg(jrd.status order by jrd.start_time desc))[1],
                 'last_run', max(jrd.start_time),
                 'last_error', left(coalesce(
                   (array_agg(jrd.return_message order by jrd.start_time desc)
                     filter (where jrd.status = 'failed'))[1], ''
                 ), 300)
               ) as obj,
               count(*) filter (where jrd.status = 'failed') as fails
          from cron.job j
          join cron.job_run_details jrd on jrd.jobid = j.jobid
         where jrd.start_time > now() - make_interval(hours => p_lookback_hours)
         group by j.jobid, j.command
        having count(*) filter (where jrd.status = 'failed') > 0
      ) x
    ), '[]'::jsonb),
    'recent_alerts', coalesce((
      select jsonb_agg(y.obj order by y.created_at desc)
      from (
        select jsonb_build_object(
                 'id', a.id,
                 'kind', a.kind,
                 'severity', a.severity,
                 'job_name', a.job_name,
                 'message', a.message,
                 'acknowledged', a.acknowledged_at is not null,
                 'created_at', a.created_at
               ) as obj,
               a.created_at
          from public.admin_alerts a
         order by a.created_at desc
         limit 20
      ) y
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_delete_anon_user
CREATE OR REPLACE FUNCTION public.admin_delete_anon_user(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_is_reg boolean;
  v_is_dummy boolean;
  v_nick text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(p.is_registered, false), coalesce(p.nickname, '')
    into v_is_reg, v_nick
    from public.profiles p
   where p.id = p_uid;

  if v_nick = '' and not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  -- Cek DUMMY lebih dulu: dummy bisa `is_registered=true` (dibuat admin).
  select exists(select 1 from public.dummy_accounts d where d.uid = p_uid)
    into v_is_dummy;
  if v_is_dummy then
    return jsonb_build_object('ok', false, 'error', 'DUMMY');
  end if;

  if v_is_reg then
    return jsonb_build_object('ok', false, 'error', 'REGISTERED');
  end if;

  perform public.fn_archive_deleted_user(p_uid, 'admin_delete');

  -- Chat lawan dipertahankan sebagai penanda (isi pesan dihapus).
  perform public.mark_chats_user_deleted(p_uid);

  delete from public.room_presence where user_id = p_uid;
  delete from public.blocks where blocker_id = p_uid or blocked_id = p_uid;
  delete from public.reports where reporter_id = p_uid or reported_id = p_uid;
  delete from public.user_photos where user_id = p_uid;
  delete from public.user_devices where user_id = p_uid;
  delete from public.user_location_history where user_id = p_uid;
  delete from public.contact_messages where user_id = p_uid;

  delete from public.profiles where id = p_uid;

  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from auth.users where id = p_uid;

  delete from public.admin_stats_cache where id = 1;

  return jsonb_build_object('ok', true, 'nickname', v_nick);
end;
$function$

-- snapshot-fn: admin_delete_chat
CREATE OR REPLACE FUNCTION public.admin_delete_chat(p_chat_id text, p_delete_user_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  admin_email text := coalesce(auth.email(),'');
  photo_paths jsonb := '[]'::jsonb;
  v_uid uuid;
  v_parts uuid[];
begin
  if admin_email != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select participants into v_parts
  from public.private_chats where chat_id = p_chat_id;

  select coalesce(jsonb_agg(image_data), '[]'::jsonb) into photo_paths
  from private_messages
  where chat_id = p_chat_id
    and image_data like 'chat/%';

  delete from public.private_messages where chat_id = p_chat_id;
  delete from public.private_chats where chat_id = p_chat_id;

  -- AI cleanup utk dummy peserta chat ini (manusia biasa: no-op).
  if v_parts is not null then
    delete from public.ai_memory where dummy_uid = any (v_parts);
    delete from public.ai_reply_claims where dummy_uid = any (v_parts);
  end if;
  delete from public.ai_chat_state where chat_id = p_chat_id;
  delete from public.chat_ai_pause where chat_id = p_chat_id;

  if array_length(p_delete_user_ids, 1) is not null then
    set local session_replication_role = 'replica';

    foreach v_uid in array p_delete_user_ids loop
      if exists (
        select 1 from auth.users where id = v_uid and email = 'zunixe@gmail.com'
      ) then
        continue;
      end if;
      perform public.fn_archive_deleted_user(v_uid, 'admin_delete');
      delete from public.ai_memory where dummy_uid = v_uid or user_id = v_uid;
      delete from public.ai_chat_state where chat_id in (
        select chat_id from public.private_chats where v_uid = any (participants)
      );
      delete from public.room_presence where user_id = v_uid;
      delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
      delete from public.reports where reporter_id = v_uid or reported_id = v_uid;
      delete from public.user_photos where user_id = v_uid;
      delete from public.private_chats where v_uid = any (participants);
      delete from public.private_messages where sender_id = v_uid;
      delete from public.coin_ledger where user_id = v_uid;
      delete from public.point_events where user_id = v_uid;
      delete from public.topup_orders where user_id = v_uid;
      delete from public.dummy_accounts where uid = v_uid;
      delete from public.profiles where id = v_uid;
      delete from auth.users where id = v_uid;
    end loop;

    set local session_replication_role = 'origin';
  end if;

  return jsonb_build_object('ok', true, 'photo_paths', photo_paths);
end;
$function$

-- snapshot-fn: admin_delete_dummy
CREATE OR REPLACE FUNCTION public.admin_delete_dummy(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_chats int;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  perform public.fn_archive_deleted_user(p_uid, 'dummy_delete');

  -- Chat lawan dipertahankan sebagai penanda (isi pesan dihapus).
  v_chats := public.mark_chats_user_deleted(p_uid);

  delete from public.room_presence where user_id = p_uid;
  delete from public.user_photos where user_id = p_uid;

  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from public.dummy_accounts where uid = p_uid;
  delete from auth.users where id = p_uid;

  return jsonb_build_object('ok', true, 'chats_deleted', v_chats);
end;
$function$

-- snapshot-fn: admin_delete_room
CREATE OR REPLACE FUNCTION public.admin_delete_room(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  admin_email text := coalesce(auth.email(), '');
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if admin_email <> 'zunixe@gmail.com' then raise exception 'Not admin'; end if;

  -- Idempoten: kalau sudah tidak ada, tidak error.
  delete from public.rooms where id = p_room_id;
end;
$function$

-- snapshot-fn: admin_delete_room_message
CREATE OR REPLACE FUNCTION public.admin_delete_room_message(p_message_id bigint, p_deleted boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rows int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update public.messages
    set is_deleted = p_deleted
    where id = p_message_id;

  get diagnostics rows = row_count;

  return jsonb_build_object('ok', rows > 0, 'rows', rows);
end;
$function$

-- snapshot-fn: admin_deleted_device_history
CREATE OR REPLACE FUNCTION public.admin_deleted_device_history(p_nickname text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_arch jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  -- Snapshot arsip terbaru untuk nickname ini (hasil hapus baru).
  select d.devices into v_arch
    from public.deleted_users d
   where d.nickname = p_nickname
   order by d.deleted_at desc
   limit 1;
  if v_arch is not null and jsonb_array_length(coalesce(v_arch,'[]'::jsonb)) > 0 then
    return v_arch;
  end if;
  -- Fallback: baris live yatim (arsip lama sebelum kolom devices ada).
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'install_id', d.install_id,
      'brand', d.brand,
      'model', d.model,
      'os_name', d.os_name,
      'os_version', d.os_version,
      'app_version', d.app_version,
      'ip_address', d.ip_address,
      'last_seen_at', d.last_seen_at,
      'nickname_snapshot', d.nickname_snapshot,
      'is_active', d.is_active
    ) order by d.last_seen_at desc nulls last
  ), '[]'::jsonb) into result
  from public.user_devices d
  where d.nickname_snapshot = p_nickname;
  return result;
end;
$function$

-- snapshot-fn: admin_deleted_location_history
CREATE OR REPLACE FUNCTION public.admin_deleted_location_history(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(d.locations,'[]'::jsonb) into result
    from public.deleted_users d
   where d.user_id = p_user_id
   limit 1;
  if result is null then
    result := '[]'::jsonb;
  end if;
  return result;
end;
$function$

-- snapshot-fn: admin_dummy_uids
CREATE OR REPLACE FUNCTION public.admin_dummy_uids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select uid from public.dummy_accounts
$function$

-- snapshot-fn: admin_email_campaign_delete
CREATE OR REPLACE FUNCTION public.admin_email_campaign_delete(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  delete from email_campaigns where id = p_id;
  return jsonb_build_object('ok', true);
end; $function$

-- snapshot-fn: admin_email_campaign_detail
CREATE OR REPLACE FUNCTION public.admin_email_campaign_detail(p_id bigint, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c jsonb; rec jsonb;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select jsonb_build_object(
    'id', id, 'name', name, 'subject', subject, 'html_body', html_body,
    'segment', segment, 'status', status, 'created_at', created_at,
    'sent_at', sent_at, 'total_recipients', total_recipients,
    'sent_count', sent_count, 'delivered_count', delivered_count,
    'open_count', open_count, 'click_count', click_count,
    'bounce_count', bounce_count, 'unsub_count', unsub_count, 'last_error', last_error
  ) into c from email_campaigns where id = p_id;
  if c is null then raise exception 'Campaign not found'; end if;

  select coalesce(jsonb_agg(y order by y.sent_at desc nulls last), '[]'::jsonb) into rec
  from (
    select r.id, r.uid, r.email, r.status, r.sent_at, r.opened_at, r.clicked_at, r.error
    from email_recipients r
    where r.campaign_id = p_id
    order by r.sent_at desc nulls last
    limit greatest(1, least(p_limit, 500)) offset greatest(0, p_offset)
  ) y;

  return jsonb_build_object('campaign', c, 'recipients', rec);
end; $function$

-- snapshot-fn: admin_email_campaign_save
CREATE OR REPLACE FUNCTION public.admin_email_campaign_save(p_id bigint, p_name text, p_subject text, p_html text, p_segment jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); new_id bigint;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  if p_id is null or p_id = 0 then
    insert into email_campaigns (name, subject, html_body, segment, created_by)
      values (coalesce(p_name,''), coalesce(p_subject,''), coalesce(p_html,''),
              coalesce(p_segment, '{"type":"all_registered"}'::jsonb), me)
      returning id into new_id;
  else
    update email_campaigns set
      name = coalesce(p_name,''),
      subject = coalesce(p_subject,''),
      html_body = coalesce(p_html,''),
      segment = coalesce(p_segment, segment),
      updated_at = now()
    where id = p_id
    returning id into new_id;
  end if;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $function$

-- snapshot-fn: admin_email_campaigns_page
CREATE OR REPLACE FUNCTION public.admin_email_campaigns_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select c.id, c.name, c.subject, c.segment, c.status, c.created_at, c.sent_at,
           c.total_recipients, c.sent_count, c.delivered_count, c.open_count,
           c.click_count, c.bounce_count, c.unsub_count
    from email_campaigns c
    order by c.created_at desc
    limit greatest(1, least(p_limit, 200)) offset greatest(0, p_offset)
  ) x;
  return res;
end; $function$

-- snapshot-fn: admin_email_enqueue
CREATE OR REPLACE FUNCTION public.admin_email_enqueue(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; n int; enabled boolean;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select * into c from email_campaigns where id = p_id;
  if c is null then raise exception 'Campaign not found'; end if;
  if c.status in ('queued','sending','sent') then
    return jsonb_build_object('ok', false, 'reason', 'already_' || c.status);
  end if;
  if coalesce(c.subject,'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no_subject');
  end if;
  if coalesce(c.html_body,'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no_body');
  end if;

  select email_marketing_enabled into enabled from app_settings where id = 'global';
  if enabled is not true then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;

  -- Bersihkan penerima lama (kalau re-enqueue setelah reset).
  delete from email_recipients where campaign_id = p_id;

  -- Snapshot penerima: registered + email + bukan suppression.
  insert into email_recipients (campaign_id, uid, email)
  select p_id, p.id, p.email
  from profiles p
  where p.is_registered = true
    and coalesce(p.email,'') <> ''
    and not exists (select 1 from email_suppressions s where s.email = p.email)
    and (
      coalesce(c.segment->>'type','all_registered') <> 'active_days'
      or p.last_seen >= now() - make_interval(days => greatest(1, coalesce((c.segment->>'days')::int, 30)))
    )
  on conflict (campaign_id, email) do nothing;

  select count(*) into n from email_recipients where campaign_id = p_id;

  update email_campaigns set
    status = 'queued', total_recipients = n, sent_count = 0,
    delivered_count = 0, open_count = 0, click_count = 0,
    bounce_count = 0, unsub_count = 0, last_error = null, updated_at = now()
  where id = p_id;

  -- Tandai siap kirim di outbox (email-worker mengurasnya).
  insert into outbox (type, payload) values (
    'email_batch',
    jsonb_build_object('campaign_id', p_id)
  );

  return jsonb_build_object('ok', true, 'recipients', n);
end; $function$

-- snapshot-fn: admin_email_estimate_segment
CREATE OR REPLACE FUNCTION public.admin_email_estimate_segment(p_segment jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int; t text; days int;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  t := coalesce(p_segment->>'type', 'all_registered');
  if t = 'active_days' then
    days := greatest(1, coalesce((p_segment->>'days')::int, 30));
    select count(*) into n from profiles p
      where p.is_registered = true
        and coalesce(p.email,'') <> ''
        and p.last_seen >= now() - make_interval(days => days)
        and not exists (select 1 from email_suppressions s where s.email = p.email);
  else
    select count(*) into n from profiles p
      where p.is_registered = true
        and coalesce(p.email,'') <> ''
        and not exists (select 1 from email_suppressions s where s.email = p.email);
  end if;
  return jsonb_build_object('count', n);
end; $function$

-- snapshot-fn: admin_email_stats
CREATE OR REPLACE FUNCTION public.admin_email_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  if not public._email_is_admin() then raise exception 'Forbidden'; end if;
  select jsonb_build_object(
    'campaigns', count(*),
    'sent_total', coalesce(sum(sent_count),0),
    'delivered_total', coalesce(sum(delivered_count),0),
    'open_total', coalesce(sum(open_count),0),
    'click_total', coalesce(sum(click_count),0),
    'bounce_total', coalesce(sum(bounce_count),0),
    'unsub_total', coalesce(sum(unsub_count),0),
    'suppressed', (select count(*) from email_suppressions),
    'registered_with_email', (
      select count(*) from profiles
      where is_registered = true and coalesce(email,'') <> ''
    )
  ) into res
  from email_campaigns;
  return res;
end; $function$

-- snapshot-fn: admin_exclude_device_cascade
CREATE OR REPLACE FUNCTION public.admin_exclude_device_cascade(p_install_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_install text := nullif(trim(coalesce(p_install_id, '')), '');
  v_devices jsonb;
  v_uids jsonb;
  v_added jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if v_install is null then
    raise exception 'p_install_id kosong';
  end if;

  -- Tambah install_id ke excluded_devices (unik).
  select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into v_devices
    from (
      select jsonb_array_elements_text(
               case when jsonb_typeof(excluded_devices) = 'array'
                    then excluded_devices else '[]'::jsonb end) as x
        from public.app_settings where id = 'global'
      union
      select v_install
    ) t;

  -- Kumpulkan SEMUA uid yang pernah login di device ini → tambah ke
  -- excluded_uids supaya exclude tahan walau install_id berubah.
  select coalesce(jsonb_agg(distinct u::text), '[]'::jsonb) into v_uids
    from (
      select jsonb_array_elements_text(
               case when jsonb_typeof(excluded_uids) = 'array'
                    then excluded_uids else '[]'::jsonb end) as u
        from public.app_settings where id = 'global'
      union
      select d.user_id::text
        from public.user_devices d
       where d.install_id = v_install
         and d.user_id is not null
    ) s
   where u ~* '^[0-9a-f-]{36}$';

  update public.app_settings
     set excluded_devices = coalesce(v_devices, '[]'::jsonb),
         excluded_uids    = coalesce(v_uids, '[]'::jsonb),
         updated_at       = now()
   where id = 'global';

  -- Ringkasan langsung segar.
  delete from public.admin_stats_cache where id = 1;

  v_added := coalesce(v_uids, '[]'::jsonb);
  return jsonb_build_object('devices', v_devices, 'uids', v_added);
end;
$function$

-- snapshot-fn: admin_excluded_uids
CREATE OR REPLACE FUNCTION public.admin_excluded_uids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select d.user_id
  from public.user_devices d
  where d.install_id in (
    select jsonb_array_elements_text(excluded_devices)
    from public.app_settings where id = 'global'
  )
  group by d.user_id
  union
  select value::uuid
  from public.app_settings,
       lateral jsonb_array_elements_text(
         case when jsonb_typeof(excluded_uids) = 'array'
              then excluded_uids else '[]'::jsonb end
       ) as value
  where id = 'global'
    and value ~* '^[0-9a-f-]{36}$';
$function$

-- snapshot-fn: admin_flag_shared_locations
CREATE OR REPLACE FUNCTION public.admin_flag_shared_locations(p_min_users integer DEFAULT 3)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
begin
  if coalesce(auth.email(),'') <> 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  with grp as (
    select round(lat_gps::numeric, 4) la, round(lon_gps::numeric, 4) lo,
           count(*) n
      from public.profiles
     where lat_gps is not null and loc_source = 'gps'
     group by 1, 2
    having count(*) >= greatest(coalesce(p_min_users,3), 2)
  )
  update public.profiles p
     set location_mocked = true,
         location_mock_reason =
           case when p.location_mock_reason is null
                  or p.location_mock_reason = ''
                then 'shared_coord'
                when position('shared_coord' in p.location_mock_reason) > 0
                then p.location_mock_reason
                else p.location_mock_reason || ',shared_coord' end,
         location_flagged_at = coalesce(p.location_flagged_at, now())
    from grp g
   where round(p.lat_gps::numeric, 4) = g.la
     and round(p.lon_gps::numeric, 4) = g.lo
     and p.loc_source = 'gps'
     and p.location_mocked = false;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$

-- snapshot-fn: admin_get_ai_reply_log
CREATE OR REPLACE FUNCTION public.admin_get_ai_reply_log(p_chat_id text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rows jsonb[];
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(t.j order by t.id desc), '{}'::jsonb[]) into v_rows
  from (
    select l.id,
      jsonb_build_object(
        'created_at', l.created_at,
        'chat_id', l.chat_id,
        'trigger_msg_id', l.trigger_msg_id,
        'sender_id', l.sender_id,
        'dummy_uid', l.dummy_uid,
        'nickname', (select d.nickname from public.dummy_accounts d where d.uid = l.dummy_uid),
        'proactive', l.proactive,
        'stage', l.stage,
        'decision', l.decision,
        'detail', l.detail
      ) as j
    from public.ai_reply_log l
    where (p_chat_id is null or l.chat_id = p_chat_id)
    order by l.id desc
    limit least(coalesce(p_limit, 100), 500)
  ) t;
  return v_rows;
end;
$function$

-- snapshot-fn: admin_get_chat_last_read
CREATE OR REPLACE FUNCTION public.admin_get_chat_last_read(p_chat_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(last_read_at, '{}'::jsonb) into result
  from public.private_chats
  where chat_id = p_chat_id;

  return coalesce(result, '{}'::jsonb);
end;
$function$

-- snapshot-fn: admin_get_chat_messages_page
CREATE OR REPLACE FUNCTION public.admin_get_chat_messages_page(p_chat_id text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'chat_id', m.chat_id,
      'sender_id', m.sender_id,
      'sender_name', m.sender_name,
      'sender_gender', m.sender_gender,
      'text', m.text,
      'type', m.type,
      'is_deleted', m.is_deleted,
      'edited', m.edited,
      -- PATH storage: dipakai admin untuk unduh foto/video (foto biasa &
      -- video tidak lagi kosong di monitor).
      'image_path', m.image_path,
      -- data inline: view-once foto/video tetap utuh (admin boleh lihat
      -- walau sudah kadaluarsa); tipe lain dikosongkan (lazy via path).
      'image_data', case
        when m.type in (
          'view_once','view_once_expired',
          'video_once','video_once_expired'
        ) then m.image_data
        else ''
      end,
      'voice_path', m.voice_path,
      'duration_ms', m.duration_ms,
      'created_at', m.created_at,
      'replied_to_id', m.replied_to_id,
      'replied_to_text', m.replied_to_text,
      'replied_to_sender_name', m.replied_to_sender_name
    ) order by m.created_at desc
  ), '[]'::jsonb) into result
  from (
    select m.*
    from private_messages m
    where m.chat_id = p_chat_id
    order by m.created_at desc
    limit p_limit offset p_offset
  ) m;

  return result;
end;
$function$

-- snapshot-fn: admin_get_chat_org
CREATE OR REPLACE FUNCTION public.admin_get_chat_org()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v public.admin_chat_org;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select * into v from public.admin_chat_org where id = 'global';
  if v is null then
    return jsonb_build_object(
      'pinned_chat_ids', '[]'::jsonb,
      'category_list', '[]'::jsonb,
      'category_map', '{}'::jsonb
    );
  end if;
  return jsonb_build_object(
    'pinned_chat_ids', to_jsonb(coalesce(v.pinned_chat_ids, '{}')),
    'category_list', to_jsonb(coalesce(v.category_list, '{}')),
    'category_map', coalesce(v.category_map, '{}'::jsonb)
  );
end;
$function$

-- snapshot-fn: admin_get_dummy_stories
CREATE OR REPLACE FUNCTION public.admin_get_dummy_stories(p_uid text, p_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid;
  v_days int := greatest(1, least(coalesce(p_days, 14), 60));
  v_result jsonb;
  v_kind text;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;

  v_uid := p_uid::uuid;

  select coalesce(kind, 'regular') into v_kind
    from public.dummy_accounts where uid = v_uid;
  if v_kind is null then v_kind := 'regular'; end if;

  -- Bangun daftar hari (WIB) terakhir, LEFT JOIN story per hari.
  select coalesce(jsonb_agg(row_json order by d_date desc), '[]'::jsonb)
  into v_result
  from (
    select
      to_char(days.d_date, 'YYYY-MM-DD') as d_date,
      jsonb_build_object(
        'date', to_char(days.d_date, 'YYYY-MM-DD'),
        'has_story', (s.story is not null),
        'story', s.story,
        'created_at', s.created_at
      ) as row_json
    from (
      select ((now() + interval '7 hours')::date - (g.i || ' days')::interval)::date as d_date
      from generate_series(0, v_days - 1) as g(i)
    ) days
    left join public.ai_daily_story s
      on s.dummy_uid = v_uid
     and s.story_date = days.d_date
  ) x;

  return jsonb_build_object(
    'kind', v_kind,
    'story_expected', (v_kind = 'regular'),
    'days', v_result
  );
end;
$function$

-- snapshot-fn: admin_get_dummy_token
CREATE OR REPLACE FUNCTION public.admin_get_dummy_token(p_uid uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_token text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select refresh_token into v_token from public.dummy_accounts where uid = p_uid;
  return v_token;
end;
$function$

-- snapshot-fn: admin_get_excluded_devices
CREATE OR REPLACE FUNCTION public.admin_get_excluded_devices()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_list jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  select excluded_devices into v_list
    from public.app_settings where id = 'global';
  return coalesce(v_list, '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_get_excluded_uids
CREATE OR REPLACE FUNCTION public.admin_get_excluded_uids()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_list jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  select excluded_uids into v_list
    from public.app_settings where id = 'global';
  return coalesce(v_list, '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_get_location_history
CREATE OR REPLACE FUNCTION public.admin_get_location_history(p_uid uuid, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'lat', h.lat,
      'lon', h.lon,
      'source', h.loc_source,
      'at', h.created_at
    ) order by h.created_at desc
  ), '[]'::jsonb) into result
  from public.user_location_history h
  where h.user_id = p_uid
  limit greatest(p_limit, 1);
  return result;
end;
$function$

-- snapshot-fn: admin_get_message_image
CREATE OR REPLACE FUNCTION public.admin_get_message_image(p_message_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(nullif(m.image_data, ''), m.image_path) into result
  from private_messages m
  where m.id = p_message_id;

  return result;
end;
$function$

-- snapshot-fn: admin_get_point_settings
CREATE OR REPLACE FUNCTION public.admin_get_point_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $function$

-- snapshot-fn: admin_ghost_stats
CREATE OR REPLACE FUNCTION public.admin_ghost_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from auth.users u
                left join public.profiles p on p.id = u.id
               where u.is_anonymous and u.email is null and p.id is null),
    -- Hantu yang sudah cukup umur = siap dibersihkan (oleh cron 05:10).
    'purgeable', (select count(*) from auth.users u
                    left join public.profiles p on p.id = u.id
                   where u.is_anonymous and u.email is null and p.id is null
                     and u.created_at < now() - interval '24 hours'),
    -- 7 hari terakhir: berapa hantu baru lahir per hari.
    'daily_new', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day, 'n', d.n)
                       order by d.day)
      from (
        select (u.created_at at time zone 'UTC')::date as day, count(*) as n
          from auth.users u
          left join public.profiles p on p.id = u.id
         where u.is_anonymous and u.email is null and p.id is null
           and u.created_at > now() - interval '7 days'
         group by 1
      ) d
    ), '[]'::jsonb),
    -- Total anon hidup (pembanding: hantu seharusnya jauh lebih kecil).
    'anon_total', (select count(*) from auth.users
                    where is_anonymous and email is null)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_gift_revenue
CREATE OR REPLACE FUNCTION public.admin_gift_revenue()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  select jsonb_build_object(
    'total_cut', coalesce((select sum(amount) from platform_revenue where source='gift_cut'),0),
    'today_cut', coalesce((select sum(amount) from platform_revenue
       where source='gift_cut' and created_at >= current_date at time zone 'Asia/Jakarta'),0),
    'gift_count', (select count(*) from platform_revenue where source='gift_cut'),
    'cut_pct', (select gift_cut_pct from app_settings where id='global')
  ) into res;
  return res;
end; $function$

-- snapshot-fn: admin_hidden_uids
CREATE OR REPLACE FUNCTION public.admin_hidden_uids()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'dummy', coalesce((
      select jsonb_agg(du) from public.admin_dummy_uids() du), '[]'::jsonb),
    'excluded', coalesce((
      select jsonb_agg(ae) from public.admin_excluded_uids() ae), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_kyc_list
CREATE OR REPLACE FUNCTION public.admin_kyc_list(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select k.id, k.user_id, k.status, k.full_name, k.id_type, k.id_number,
           k.id_photo, k.selfie_photo, k.birth_date, k.reject_reason, k.created_at,
           p.nickname, p.email
    from kyc_requests k
    join profiles p on p.id = k.user_id
    where (p_status = 'all' or k.status = p_status)
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: admin_kyc_review
CREATE OR REPLACE FUNCTION public.admin_kyc_review(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid();
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized'; end if;

  update kyc_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    reject_reason = case when p_approve then null else p_reason end,
    reviewed_by = uid,
    reviewed_at = now(),
    updated_at = now()
  where id = p_request_id;

  if not found then raise exception 'Request not found'; end if;
  return jsonb_build_object('ok', true, 'approved', p_approve);
end; $function$

-- snapshot-fn: admin_list_chats_page
CREATE OR REPLACE FUNCTION public.admin_list_chats_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_total bigint;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  -- Estimasi murah untuk total (cukup untuk badge + hasMore admin).
  select greatest(coalesce(reltuples, 0), 0)::bigint into v_total
    from pg_class
   where oid = 'public.private_chats'::regclass;

  select jsonb_build_object(
    'total', coalesce(v_total, 0),
    'admin_uids', coalesce((
      select jsonb_agg(id) from auth.users where email = 'zunixe@gmail.com'
    ), '[]'::jsonb),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'chat_id', c.chat_id,
        'participants', c.participants,
        'participant_names', c.participant_names,
        'participant_genders', c.participant_genders,
        'last_message', c.last_message,
        'last_message_at', c.effective_last,
        'message_count', c.msg_count
      ) order by c.effective_last desc nulls last
    ), '[]'::jsonb)
  ) into result
  from (
    select
      c.chat_id,
      c.participants,
      c.participant_names,
      c.participant_genders,
      c.last_message,
      c.last_message_at,
      coalesce(m.last_noncall, c.last_message_at) as effective_last,
      coalesce(m.msg_count, 0) as msg_count
    from public.private_chats c
    -- SATU agregasi untuk semua pesan (ganti 2× correlated per chat).
    left join (
      select
        m.chat_id as chat_id,
        count(*) as msg_count,
        max(m.created_at) filter (
          where coalesce(m.type, 'text') != 'call'
        ) as last_noncall
      from public.private_messages m
      group by m.chat_id
    ) m on m.chat_id = c.chat_id
    where c.last_message_at is not null
       or m.chat_id is not null
    order by effective_last desc nulls last
    limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) c;

  return result;
end;
$function$

-- snapshot-fn: admin_list_deleted
CREATE OR REPLACE FUNCTION public.admin_list_deleted(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_include_pending boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_archive int;
  v_pending int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select count(*) into v_archive from public.deleted_users;

  select count(*) into v_pending
    from public.profiles p
   where coalesce(p.is_registered, false) = false
     and not exists (
       select 1 from public.dummy_accounts d where d.uid = p.id
     );

  select jsonb_build_object(
    'total', v_archive + case when p_include_pending then v_pending else 0 end,
    'total_archive', v_archive,
    'total_pending', v_pending,
    -- PENTING: `page` SUDAH dipotong ORDER BY + LIMIT + OFFSET, baru
    -- diagregasi. Sebelumnya LIMIT berada di dalam subquery yang diagregasi
    -- sehingga tidak berefek (seluruh baris ikut terkirim).
    'items', coalesce((
      select jsonb_agg(page.obj order by page.sort_at desc nulls last)
      from (
        select sub.obj, sub.sort_at
        from (
          -- (a) Arsip user terhapus.
          select
            jsonb_build_object(
              'user_id', d.user_id,
              'nickname', d.nickname,
              'email', d.email,
              'is_registered', d.is_registered,
              'brand', d.brand,
              'model', d.model,
              'ip_address', d.ip_address,
              'last_seen_at', d.last_seen_at,
              'created_at', d.created_at,
              'deleted_at', d.deleted_at,
              'reason', d.reason,
              'claimed_by', d.claimed_by,
              'claimed_nick', d.claimed_nick,
              'pending', false,
              'device_count', coalesce(jsonb_array_length(d.devices), 0),
              'location_count', coalesce(jsonb_array_length(d.locations), 0)
            ) as obj,
            d.deleted_at as sort_at
          from public.deleted_users d

          union all

          -- (b) Anon belum dihapus (pending) — hanya bila diminta.
          select
            jsonb_build_object(
              'user_id', p.id,
              'nickname', p.nickname,
              'email', p.email,
              'is_registered', coalesce(p.is_registered, false),
              'brand', '',
              'model', '',
              'ip_address', coalesce(p.ip_address, ''),
              'last_seen_at', p.last_seen,
              'created_at', p.created_at,
              'deleted_at', null,
              'reason', 'pending_anon',
              'claimed_by', null,
              'claimed_nick', null,
              'pending', true,
              'status', p.status,
              'country', p.country,
              'city', p.city,
              'device_count', 0,
              'location_count', 0
            ) as obj,
            p.last_seen as sort_at
          from public.profiles p
          where p_include_pending
            and coalesce(p.is_registered, false) = false
            and not exists (
              select 1 from public.dummy_accounts d where d.uid = p.id
            )
        ) sub
        -- Urutkan & potong DI LEVEL INI (bukan di dalam agregasi).
        order by sub.sort_at desc nulls last
        limit greatest(p_limit, 1)
        offset greatest(p_offset, 0)
      ) page
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_list_devices
CREATE OR REPLACE FUNCTION public.admin_list_devices(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_total bigint;
  v_excl uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  select greatest(count(*), 0)::bigint into v_total
    from public.user_devices d
    where d.install_id not in (
      select jsonb_array_elements_text(excluded_devices)
      from public.app_settings where id = 'global'
    )
      and (d.user_id is null or not (d.user_id = any(v_excl)));

  select jsonb_build_object(
    'total', coalesce(v_total, 0),
    'items', coalesce((
      select jsonb_agg(sub.obj order by sub.last_seen_at desc nulls last)
      from (
        select
          jsonb_build_object(
            'user_id',      p.id,
            'nickname',     p.nickname,
            'email',        p.email,
            'is_registered', p.is_registered,
            'profile_status', p.status,
            'install_id',   d.install_id,
            'brand',        d.brand,
            'model',        d.model,
            'os_name',      d.os_name,
            'os_version',   d.os_version,
            'app_version',  d.app_version,
            'ip_address',   d.ip_address,
            'last_seen_at', d.last_seen_at,
            'is_active',    d.is_active,
            'created_at',   d.created_at
          ) as obj,
          d.last_seen_at
        from public.user_devices d
        left join public.profiles p on p.id = d.user_id
        where d.install_id not in (
          select jsonb_array_elements_text(excluded_devices)
          from public.app_settings where id = 'global'
        )
          and (d.user_id is null or not (d.user_id = any(v_excl)))
        order by d.last_seen_at desc nulls last
        limit greatest(p_limit, 1) offset greatest(p_offset, 0)
      ) sub
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_list_dummies
CREATE OR REPLACE FUNCTION public.admin_list_dummies()
 RETURNS jsonb[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_rows jsonb[];
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'gender', p.gender,
    'age', p.age,
    'city', p.city,
    'country', p.country,
    'unread', coalesce((
      select sum(coalesce((c.unread_counts ->> d.uid::text)::int, 0))
      from public.private_chats c
      where d.uid = any (c.participants)
    ), 0),
    'kind', coalesce(d.kind, 'regular'),
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_guard_enabled', d.ai_guard_enabled,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true),
    'ai_always_online', coalesce(d.ai_always_online, false),
    'ai_no_rate_limit', coalesce(d.ai_no_rate_limit, false),
    'ai_max_replies', d.ai_max_replies,
    'ai_min_interval', d.ai_min_interval,
    'ai_always_reply', coalesce(d.ai_always_reply, false),
    'ai_wake_until', d.ai_wake_until,
    'ai_photos_enabled', coalesce(d.ai_photos_enabled, true)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$function$

-- snapshot-fn: admin_list_dummies_page
CREATE OR REPLACE FUNCTION public.admin_list_dummies_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_items jsonb[];
  v_total int;
  v_limit int := greatest(1, least(coalesce(p_limit, 50), 200));
  v_offset int := greatest(0, coalesce(p_offset, 0));
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;

  select count(*) into v_total from public.dummy_accounts;

  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'gender', p.gender,
    'age', p.age,
    'city', p.city,
    'country', p.country,
    'unread', coalesce(u.unread, 0),
    'kind', coalesce(d.kind, 'regular'),
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_guard_enabled', d.ai_guard_enabled,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true),
    'ai_always_online', coalesce(d.ai_always_online, false),
    'ai_no_rate_limit', coalesce(d.ai_no_rate_limit, false),
    'ai_max_replies', d.ai_max_replies,
    'ai_min_interval', d.ai_min_interval,
    'ai_always_reply', coalesce(d.ai_always_reply, false),
    'ai_wake_until', d.ai_wake_until,
    'ai_photos_enabled', coalesce(d.ai_photos_enabled, true)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_items
  from (
    select * from public.dummy_accounts
    order by created_at desc
    limit v_limit offset v_offset
  ) d
  join public.profiles p on p.id = d.uid
  -- SATU agregasi untuk seluruh halaman (ganti 50× correlated subquery).
  left join (
    select dp.uid as uid,
           sum(coalesce((c.unread_counts ->> dp.uid::text)::int, 0)) as unread
      from (
        select uid from public.dummy_accounts
        order by created_at desc
        limit v_limit offset v_offset
      ) dp
      join public.private_chats c on dp.uid = any (c.participants)
     group by dp.uid
  ) u on u.uid = d.uid;

  return jsonb_build_object(
    'items', coalesce(v_items, '{}'::jsonb[]),
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset
  );
end;
$function$

-- snapshot-fn: admin_list_private_rooms_page
CREATE OR REPLACE FUNCTION public.admin_list_private_rooms_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_search text DEFAULT ''::text, p_country text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  q text := coalesce(trim(p_search),'');
  ctry text := coalesce(trim(p_country),'');
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (
      select count(*) from public.rooms r
      where r.is_private = true
        and (q = '' or r.name ilike '%'||q||'%' or r.owner_name ilike '%'||q||'%')
        and (ctry = '' or r.country = ctry)
    ),
    'items', coalesce(jsonb_agg(room_obj order by sort_at desc), '[]'::jsonb)
  )
  into result
  from (
    select
      jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'icon', r.icon,
        'owner_id', r.owner_id,
        'owner_name', r.owner_name,
        'country', r.country,
        'category', r.category,
        'has_password', r.has_password,
        'expires_at', r.expires_at,
        'created_at', r.created_at,
        'member_count', (select count(*) from public.room_members m where m.room_id = r.id),
        'message_count', (select count(*) from public.messages msg where msg.room_id = r.id),
        'last_message_at', (select max(msg.created_at) from public.messages msg where msg.room_id = r.id),
        'last_message', (
          select case
            when msg.is_deleted then coalesce(nullif(msg.text,''),'') -- tetap teks; UI tandai terhapus
            when msg.type = 'image' then '[Foto]'
            when msg.type = 'video' then '[Video]'
            when msg.type = 'voice' then '[Voice]'
            when msg.type in ('view_once','view_once_expired') then '[Sekali Lihat]'
            else coalesce(msg.text,'')
          end
          from public.messages msg
          where msg.room_id = r.id
          order by msg.created_at desc
          limit 1
        ),
        'last_message_sender', (
          select msg.sender_name
          from public.messages msg
          where msg.room_id = r.id
          order by msg.created_at desc
          limit 1
        )
      ) as room_obj,
      coalesce(
        (select max(msg.created_at) from public.messages msg where msg.room_id = r.id),
        r.created_at
      ) as sort_at
    from public.rooms r
    where r.is_private = true
      and (q = '' or r.name ilike '%'||q||'%' or r.owner_name ilike '%'||q||'%')
      and (ctry = '' or r.country = ctry)
    order by sort_at desc
    limit p_limit offset p_offset
  ) s;

  return coalesce(result, jsonb_build_object('total',0,'items','[]'::jsonb));
end;
$function$

-- snapshot-fn: admin_location_sources
CREATE OR REPLACE FUNCTION public.admin_location_sources()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'gps', (select count(*) from public.profiles where lat_gps is not null),
    'ip',  (select count(*) from public.profiles where lat_ip is not null),
    'none',(select count(*) from public.profiles
             where lat_gps is null and lat_ip is null),
    'history', (select count(*) from public.user_location_history),
    'history_gps', (select count(*) from public.user_location_history
                     where loc_source = 'gps')
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_mark_chat_read
CREATE OR REPLACE FUNCTION public.admin_mark_chat_read(p_chat_id text, p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  update public.private_chats
  set unread_counts = jsonb_set(coalesce(unread_counts, '{}'::jsonb), array[p_uid::text], '0'::jsonb),
      last_read_at = jsonb_set(coalesce(last_read_at, '{}'::jsonb), array[p_uid::text], to_jsonb(now()::text))
  where chat_id = p_chat_id;
end;
$function$

-- snapshot-fn: admin_mass_bonus
CREATE OR REPLACE FUNCTION public.admin_mass_bonus(bonus integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare affected int := 0; u uuid;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  for u in select id from profiles where is_registered = true loop
    perform public.ledger_credit(u, 'bonus', 'admin_mass_bonus', bonus);
    affected := affected + 1;
  end loop;
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_mass_bonus', bonus, jsonb_build_object('affected_users', affected));
  return jsonb_build_object('affected', affected, 'bonus', bonus);
end; $function$

-- snapshot-fn: admin_push_update
CREATE OR REPLACE FUNCTION public.admin_push_update()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Guard admin: is_admin_request() = pengecekan seragam seluruh RPC admin.
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  update public.app_settings
     set update_push_at = now(),
         updated_at = now()
   where id = 'global';
  return jsonb_build_object('ok', true, 'pushed_at', now());
end;
$function$

-- snapshot-fn: admin_register_dummy
CREATE OR REPLACE FUNCTION public.admin_register_dummy(p_uid uuid, p_nickname text, p_refresh_token text, p_gender text DEFAULT 'male'::text, p_age integer DEFAULT 25, p_country text DEFAULT 'Indonesia'::text, p_city text DEFAULT 'Jakarta'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_gender not in ('male', 'female') then
    raise exception 'Gender tidak valid';
  end if;
  if p_age < 18 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  if length(trim(p_nickname)) < 3 or length(p_nickname) > 20 then
    raise exception 'Nickname harus 3-20 karakter';
  end if;
  if exists (select 1 from public.profiles where lower(nickname) = lower(trim(p_nickname))) then
    raise exception 'Nickname sudah dipakai';
  end if;
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered, last_seen)
  values (p_uid, p_nickname, p_gender, p_age, p_country, p_city, 'offline', true, now())
  on conflict (id) do update set
    nickname = excluded.nickname,
    gender = excluded.gender,
    age = excluded.age,
    country = excluded.country,
    city = excluded.city,
    last_seen = now();
  insert into public.dummy_accounts (uid, nickname, refresh_token)
  values (p_uid, p_nickname, p_refresh_token)
  on conflict (uid) do update set
    nickname = excluded.nickname,
    refresh_token = excluded.refresh_token;
  return jsonb_build_object('ok', true, 'uid', p_uid);
end;
$function$

-- snapshot-fn: admin_registration_kpis
CREATE OR REPLACE FUNCTION public.admin_registration_kpis()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  v_reg int;
  v_anon int;
  v_month_new int;
  v_prev_month_new int;
  v_today_new int;
  v_best_day int;
  v_best_count int;
  v_days_elapsed int;
  v_avg numeric;
  v_active_today int;
  v_male int;
  v_female int;
  v_other int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  -- Terdaftar (nyata) & anonim (nyata) — untuk konversi.
  select count(*) into v_reg from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy));
  select count(*) into v_anon from public.profiles p
   where p.is_registered = false
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy));

  -- Distribusi gender user TERDAFTAR (nyata).
  select
    count(*) filter (where p.gender = 'male'),
    count(*) filter (where p.gender = 'female'),
    count(*) filter (where p.gender is distinct from 'male'
                        and p.gender is distinct from 'female')
    into v_male, v_female, v_other
    from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy));

  -- Baru bulan ini & bulan lalu.
  select count(*) into v_month_new from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and date_trunc('month', p.created_at) = date_trunc('month', now());
  select count(*) into v_prev_month_new from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and date_trunc('month', p.created_at) = date_trunc('month', now() - interval '1 month');

  -- Baru hari ini.
  select count(*) into v_today_new from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and p.created_at::date = now()::date;

  -- Hari terbaik bulan ini.
  select extract(day from p.created_at)::int, count(*)::int
    into v_best_day, v_best_count
    from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and date_trunc('month', p.created_at) = date_trunc('month', now())
   group by 1
   order by 2 desc, 1 asc
   limit 1;

  -- Rata-rata/hari bulan ini (bagi jumlah hari yang sudah berjalan).
  v_days_elapsed := extract(day from now())::int;
  v_avg := case when v_days_elapsed > 0
                then round(v_month_new::numeric / v_days_elapsed, 1)
                else 0 end;

  -- Aktif hari ini (registered nyata yang last_seen hari ini).
  select count(*) into v_active_today from public.profiles p
   where p.is_registered = true
     and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
     and p.last_seen::date = now()::date;

  return jsonb_build_object(
    'registered_total', v_reg,
    'anon_total', v_anon,
    'conversion_pct', case when (v_reg + v_anon) > 0
        then round(v_reg::numeric * 100 / (v_reg + v_anon), 1) else 0 end,
    'new_this_month', v_month_new,
    'new_prev_month', v_prev_month_new,
    -- Delta % vs bulan lalu (bulan berjalan vs bulan penuh lalu → indikatif).
    'mom_pct', case when v_prev_month_new > 0
        then round((v_month_new - v_prev_month_new)::numeric * 100 / v_prev_month_new, 1)
        else null end,
    'new_today', v_today_new,
    'avg_per_day', v_avg,
    'best_day', v_best_day,
    'best_day_count', coalesce(v_best_count, 0),
    'active_today', v_active_today,
    'male_total', v_male,
    'female_total', v_female,
    'other_gender_total', v_other,
    'days_elapsed', v_days_elapsed
  );
end;
$function$

-- snapshot-fn: admin_registrations_daily
CREATE OR REPLACE FUNCTION public.admin_registrations_daily(p_year integer, p_month integer)
 RETURNS TABLE(day integer, count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'forbidden';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;
  return query
    select extract(day from p.created_at)::int as d,
           count(*)::bigint as c
      from profiles p
     where p.is_registered = true
       and not (p.id = any(v_excl))
       and not (p.id = any(v_dummy))
       and extract(year from p.created_at) = p_year
       and extract(month from p.created_at) = p_month
     group by 1
     order by 1;
end;
$function$

-- snapshot-fn: admin_registrations_list
CREATE OR REPLACE FUNCTION public.admin_registrations_list(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'total', (select count(*) from profiles
      where is_registered = true
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'user_id',     p.id,
        'nickname',    p.nickname,
        'email',       p.email,
        'gender',      p.gender,
        'age',         p.age,
        'country',     p.country,
        'city',        p.city,
        'ip_address',  p.ip_address,
        'created_at',  p.created_at,
        'last_seen_at', p.last_seen
      ) order by p.created_at desc
    ), '[]'::jsonb)
  ) into result
  from (
    select *
      from profiles
     where is_registered = true
       and not (id = any(v_excl))
       and not (id = any(v_dummy))
     order by created_at desc
     limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) p;

  return result;
end;
$function$

-- snapshot-fn: admin_registrations_monthly
CREATE OR REPLACE FUNCTION public.admin_registrations_monthly(p_months integer DEFAULT 12)
 RETURNS TABLE(ym text, year integer, month integer, count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
  v_n int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  v_n := least(greatest(coalesce(p_months, 12), 1), 24);

  -- generate_series tiap bulan, LEFT JOIN hitungan, supaya bulan kosong
  -- tetap muncul (garis tren tidak bolong).
  return query
    with m as (
      select date_trunc('month', now())::date - (i || ' months')::interval as mon
      from generate_series(0, v_n - 1) i
    )
    select
      to_char(m.mon, 'YYYY-MM') as ym,
      extract(year from m.mon)::int as year,
      extract(month from m.mon)::int as month,
      coalesce(cnt.c, 0)::bigint as count
    from m
    left join (
      select date_trunc('month', p.created_at) as mon, count(*)::bigint as c
        from public.profiles p
       where p.is_registered = true
         and not (p.id = any(v_excl)) and not (p.id = any(v_dummy))
       group by 1
    ) cnt on cnt.mon = m.mon
    order by m.mon asc;
end;
$function$

-- snapshot-fn: admin_renew_dummy_token
CREATE OR REPLACE FUNCTION public.admin_renew_dummy_token(p_uid uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin raise exception 'deprecated: renewal via edge function dummy-manage action=renew'; end; $function$

-- snapshot-fn: admin_reset_points
CREATE OR REPLACE FUNCTION public.admin_reset_points()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare affected int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  -- hapus semua ledger via truncate tidak bisa (append-only trigger blok DELETE).
  -- Sebagai gantinya: catat penyesuaian agar total tiap user = 50 bonus.
  insert into coin_ledger (user_id, bucket, type, amount, metadata)
  select w.user_id, 'bonus', 'admin_adjust', (50 - w.total_balance),
         jsonb_build_object('reason','admin_reset')
  from wallet_balances w
  where (50 - w.total_balance) <> 0;
  get diagnostics affected = row_count;

  update profiles pr set points = w.total_balance
    from wallet_balances w where w.user_id = pr.id;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_reset_all', 0, jsonb_build_object('affected_users', affected));
  return affected;
end; $function$

-- snapshot-fn: admin_revenue_overview
CREATE OR REPLACE FUNCTION public.admin_revenue_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'gift', (
      select jsonb_build_object(
        'cut_total', coalesce(sum(amount), 0),
        'cut_today', coalesce(sum(amount) filter (where created_at >= date_trunc('day', now())), 0),
        'gross_total', coalesce(sum((metadata->>'gross')::int), 0),
        'gross_today', coalesce(sum((metadata->>'gross')::int) filter (where created_at >= date_trunc('day', now())), 0),
        'count_total', count(*),
        'count_today', count(*) filter (where created_at >= date_trunc('day', now())),
        'top_gifts', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'gift', g.gift, 'count', g.cnt, 'cut', g.cut, 'gross', g.gross))
          from (
            select metadata->>'gift' as gift,
                   count(*) as cnt,
                   sum(amount) as cut,
                   sum((metadata->>'gross')::int) as gross
            from platform_revenue
            where source = 'gift_cut'
            group by metadata->>'gift'
            order by sum(amount) desc
            limit 10
          ) g
        ), '[]'::jsonb)
      )
      from platform_revenue where source = 'gift_cut'
    ),
    'withdraw', (
      select jsonb_build_object(
        'pending_count', count(*) filter (where status = 'pending'),
        'pending_payout_idr', coalesce(sum(payout_idr) filter (where status = 'pending'), 0),
        'paid_count', count(*) filter (where status = 'paid'),
        'paid_payout_idr', coalesce(sum(payout_idr) filter (where status = 'paid'), 0),
        'rejected_count', count(*) filter (where status = 'rejected'),
        'rejected_payout_idr', coalesce(sum(payout_idr) filter (where status = 'rejected'), 0)
      )
      from withdrawal_requests
    ),
    'settings', (
      select jsonb_build_object(
        'points_enabled', points_enabled,
        'gift_cut_pct', gift_cut_pct,
        'withdraw_rate_idr', withdraw_rate_idr,
        'withdraw_min_coins', withdraw_min_coins
      )
      from app_settings where id = 'global'
    )
  ) into res;

  return res;
end; $function$

-- snapshot-fn: admin_room_members
CREATE OR REPLACE FUNCTION public.admin_room_members(p_room_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'nickname', coalesce(p.nickname,'Anon'),
      'avatar', coalesce(p.avatar,''),
      'gender', coalesce(p.gender,'other'),
      'is_registered', coalesce(p.is_registered,false),
      'joined_at', m.joined_at,
      'is_owner', (m.user_id = r.owner_id)
    ) order by m.joined_at asc
  ), '[]'::jsonb)
  into result
  from public.room_members m
  left join public.profiles p on p.id = m.user_id
  left join public.rooms r on r.id = m.room_id
  where m.room_id = p_room_id;

  return result;
end;
$function$

-- snapshot-fn: admin_room_message_image
CREATE OR REPLACE FUNCTION public.admin_room_message_image(p_message_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result text;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select m.image_data into result
  from public.messages m
  where m.id = p_message_id;

  return coalesce(result,'');
end;
$function$

-- snapshot-fn: admin_room_messages_page
CREATE OR REPLACE FUNCTION public.admin_room_messages_page(p_room_id text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.messages where room_id = p_room_id),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'sender_id', m.sender_id,
        'sender_name', m.sender_name,
        'sender_gender', m.sender_gender,
        -- Foto biasa: image_data dikosongkan (load lazy via
        -- admin_room_message_image). View-once: tetap utuh (admin perlu lihat).
        'image_data', case
          when m.type in ('view_once','view_once_expired') then m.image_data
          else ''
        end,
        'image_path', coalesce(m.image_path,''),
        'voice_path', coalesce(m.voice_path,''),
        'text', m.text,
        'type', m.type,
        'duration_ms', m.duration_ms,
        'is_deleted', m.is_deleted,
        'edited', m.edited,
        'replied_to_id', m.replied_to_id,
        'replied_to_text', m.replied_to_text,
        'replied_to_sender_name', m.replied_to_sender_name,
        'created_at', m.created_at
      ) order by m.created_at desc
    ), '[]'::jsonb)
  )
  into result
  from (
    select * from public.messages
    where room_id = p_room_id
    order by created_at desc
    limit p_limit offset p_offset
  ) m;

  return coalesce(result, jsonb_build_object('total',0,'items','[]'::jsonb));
end;
$function$

-- snapshot-fn: admin_set_chat_org
CREATE OR REPLACE FUNCTION public.admin_set_chat_org(p_pinned text[] DEFAULT NULL::text[], p_categories text[] DEFAULT NULL::text[], p_map jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v public.admin_chat_org;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  insert into public.admin_chat_org (id) values ('global')
  on conflict (id) do nothing;
  update public.admin_chat_org
  set pinned_chat_ids = coalesce(p_pinned, pinned_chat_ids),
      category_list = coalesce(p_categories, category_list),
      category_map = coalesce(p_map, category_map),
      updated_at = now()
  where id = 'global'
  returning * into v;
  return jsonb_build_object(
    'pinned_chat_ids', to_jsonb(coalesce(v.pinned_chat_ids, '{}')),
    'category_list', to_jsonb(coalesce(v.category_list, '{}')),
    'category_map', coalesce(v.category_map, '{}'::jsonb)
  );
end;
$function$

-- snapshot-fn: admin_set_dummy_ai
CREATE OR REPLACE FUNCTION public.admin_set_dummy_ai(p_uid uuid, p_enabled boolean, p_persona jsonb DEFAULT '{}'::jsonb, p_schedule_auto boolean DEFAULT NULL::boolean, p_guard_enabled boolean DEFAULT NULL::boolean, p_max_replies integer DEFAULT NULL::integer, p_min_interval integer DEFAULT NULL::integer, p_no_rate_limit boolean DEFAULT NULL::boolean, p_active_hours jsonb DEFAULT NULL::jsonb, p_model text DEFAULT NULL::text, p_photos_enabled boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts where uid = p_uid) then
    raise exception 'dummy_not_found';
  end if;
  update public.dummy_accounts
  set ai_enabled = p_enabled,
      ai_persona = coalesce(p_persona, '{}'::jsonb),
      ai_schedule_auto = coalesce(p_schedule_auto, ai_schedule_auto),
      ai_guard_enabled = p_guard_enabled,
      ai_max_replies = p_max_replies,
      ai_min_interval = p_min_interval,
      ai_no_rate_limit = coalesce(p_no_rate_limit, ai_no_rate_limit),
      ai_active_hours = coalesce(p_active_hours, ai_active_hours),
      ai_photos_enabled = coalesce(p_photos_enabled, ai_photos_enabled),
      ai_model = case
        when p_model is null or p_model = '' then ai_model
        when upper(p_model) = 'NULL' then null
        else p_model
      end
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$function$

-- snapshot-fn: admin_set_dummy_status
CREATE OR REPLACE FUNCTION public.admin_set_dummy_status(p_uid uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if p_status not in ('online', 'idle', 'offline', 'invisible') then
    raise exception 'Status tidak valid';
  end if;
  update public.profiles
     set status = p_status, last_seen = now()
   where id = p_uid;
  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: admin_set_excluded_devices
CREATE OR REPLACE FUNCTION public.admin_set_excluded_devices(p_list jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_clean jsonb;
  v_uids  jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_list is null or jsonb_typeof(p_list) <> 'array' then
    raise exception 'p_list must be a JSON array';
  end if;

  -- Bersihkan daftar device: text non-kosong, trim, unik.
  select coalesce(jsonb_agg(distinct t), '[]'::jsonb) into v_clean
    from jsonb_array_elements_text(p_list) as t
    where nullif(trim(t), '') is not null;

  -- Sinkronkan excluded_uids dengan daftar device yang BARU:
  --   * uid lama yang device-nya MASIH ter-exclude → pertahankan (cascade
  --     tetap berlaku walau install_id berubah).
  --   * uid yang TIDAK punya baris device sama sekali → pertahankan (uid
  --     manual, mis. anon tanpa device).
  --   * uid yang punya device tapi device-nya tidak lagi ter-exclude → buang.
  select coalesce(jsonb_agg(distinct u), '[]'::jsonb) into v_uids
    from (
      select jsonb_array_elements_text(
               case when jsonb_typeof(excluded_uids) = 'array'
                    then excluded_uids else '[]'::jsonb end) as u
        from public.app_settings where id = 'global'
    ) s
   where u ~* '^[0-9a-f-]{36}$'
     and (
       exists (
         select 1 from public.user_devices d
          where d.user_id::text = u
            and d.install_id in (
              select jsonb_array_elements_text(v_clean)
            )
       )
       or not exists (
         select 1 from public.user_devices d
          where d.user_id::text = u
       )
     );

  update public.app_settings
     set excluded_devices = coalesce(v_clean, '[]'::jsonb),
         excluded_uids    = coalesce(v_uids, '[]'::jsonb),
         updated_at       = now()
   where id = 'global';

  -- Ringkasan langsung segar (WHERE wajib: safeupdate menolak DELETE tanpa WHERE).
  delete from public.admin_stats_cache where id = 1;

  return coalesce(v_clean, '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_set_excluded_uids
CREATE OR REPLACE FUNCTION public.admin_set_excluded_uids(p_list jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_clean jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_list is null or jsonb_typeof(p_list) <> 'array' then
    raise exception 'p_list must be a JSON array';
  end if;

  select coalesce(jsonb_agg(distinct t), '[]'::jsonb) into v_clean
    from jsonb_array_elements_text(p_list) as t
    where t ~* '^[0-9a-f-]{36}$';

  update public.app_settings
     set excluded_uids = coalesce(v_clean, '[]'::jsonb),
         updated_at = now()
   where id = 'global';

  delete from public.admin_stats_cache where id = 1;

  return coalesce(v_clean, '[]'::jsonb);
end;
$function$

-- snapshot-fn: admin_set_feature_flag
CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_feature text, p_published boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  if p_feature is null or length(trim(p_feature)) = 0 then
    raise exception 'Invalid feature';
  end if;
  update app_settings
    set feature_flags = jsonb_set(
          coalesce(feature_flags, '{}'::jsonb),
          array[p_feature],
          jsonb_build_object('published', coalesce(p_published, false)),
          true
        ),
        updated_at = now()
    where id = 'global';
  return (select feature_flags from app_settings where id = 'global');
end; $function$

-- snapshot-fn: admin_set_post_visibility
CREATE OR REPLACE FUNCTION public.admin_set_post_visibility(p_post_id uuid, p_visibility text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  -- Nilai valid sama dengan CHECK constraint tabel posts.
  if coalesce(p_visibility, '') not in ('public', 'followers', 'subscribers') then
    raise exception 'Invalid visibility';
  end if;
  update public.posts
     set visibility = p_visibility
   where id = p_post_id
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'visibility', p_visibility);
end;
$function$

-- snapshot-fn: admin_set_privacy_bypass
CREATE OR REPLACE FUNCTION public.admin_set_privacy_bypass(p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update public.app_settings
    set privacy_bypass_enabled = coalesce(p_enabled, false),
        updated_at = now()
    where id = 'global';
  return (select to_jsonb(a) from public.app_settings a where id = 'global');
end; $function$

-- snapshot-fn: admin_set_story_visibility
CREATE OR REPLACE FUNCTION public.admin_set_story_visibility(p_story_id uuid, p_state text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_exists boolean;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if p_state not in ('public','followers','friends','private') then
    raise exception 'State visibilitas tidak valid';
  end if;
  select exists(select 1 from public.stories where id = p_story_id)
    into v_exists;
  if not v_exists then
    raise exception 'Story tidak ditemukan';
  end if;

  if p_state = 'private' then
    update public.stories set owner_only = true where id = p_story_id;
  else
    update public.stories
      set owner_only = false,
          visibility = case p_state
            when 'public' then 'everyone'
            when 'followers' then 'followers'
            when 'friends' then 'friends'
          end
      where id = p_story_id;
  end if;

  return jsonb_build_object('ok', true, 'state', p_state);
end;
$function$

-- snapshot-fn: admin_stats
CREATE OR REPLACE FUNCTION public.admin_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_data jsonb;
  v_at timestamptz;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select data, refreshed_at into v_data, v_at
    from public.admin_stats_cache where id = 1;

  if v_data is null or v_at is null
     or v_at < now() - interval '5 minutes' then
    v_data := public.admin_stats_compute();
    update public.admin_stats_cache
       set data = v_data, refreshed_at = now()
     where id = 1;
  end if;

  -- info tambahan untuk UI "terakhir diperbarui"
  return jsonb_set(v_data, '{refreshed_at}',
    to_jsonb(coalesce(v_at, now())));
end;
$function$

-- snapshot-fn: admin_stats_compute
CREATE OR REPLACE FUNCTION public.admin_stats_compute()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'total_users', (select count(*) from profiles
      where not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false),
    'registered_users', (select count(*) from profiles
      where is_registered = true and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'anonymous_users', (select count(*) from profiles
      where is_registered = false and not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false),
    'messages_today',
      (select count(*) from private_messages where created_at >= current_date at time zone 'Asia/Jakarta') +
      (select count(*) from messages where created_at >= current_date at time zone 'Asia/Jakarta'),
    'rooms_active', (select count(distinct room_id) from room_presence),
    'avg_points', (select round(avg(points)) from profiles where not (id = any(v_excl))
      and not (id = any(v_dummy))),
    'total_points', (select sum(points) from profiles where not (id = any(v_excl))
      and not (id = any(v_dummy))),
    'top_earners', (select coalesce(jsonb_agg(
      jsonb_build_object('nickname', nickname, 'points', points, 'uid', id)
      order by points desc), '[]'::jsonb) from (select id, nickname, points from profiles
      where not (id = any(v_excl)) and not (id = any(v_dummy))
      order by points desc limit 10) t),
    'stuck_users', (select count(*) from profiles
      where points = 0 and is_registered = true and last_seen >= (now() - interval '7 days')
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    -- ── Laporan: nickname pelapor & terlapor (biar jelas siapa dilaporkan) ──
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object(
        'reported_id', s.reported_id,
        'report_count', s.c,
        'reported_nickname', coalesce(rp.nickname, ''),
        'reported_registered', coalesce(rp.is_registered, false),
        'reporters', s.reporters
      )
      order by s.c desc), '[]'::jsonb)
      from (
        select
          r.reported_id,
          count(*) as c,
          coalesce(jsonb_agg(distinct jsonb_build_object(
            'id', r.reporter_id,
            'nickname', coalesce(rpr.nickname, '')
          )), '[]'::jsonb) as reporters
        from public.reports r
        left join public.profiles rpr on rpr.id = r.reporter_id
        group by r.reported_id
        order by c desc
        limit 20
      ) s
      left join public.profiles rp on rp.id = s.reported_id),
    -- ── Privasi: user yang pakai setting NON-default + apa yang diatur ──
    'privacy_users', (select coalesce(jsonb_agg(
      jsonb_build_object(
        'uid', p.id,
        'nickname', p.nickname,
        'is_registered', coalesce(p.is_registered, false),
        'settings', jsonb_strip_nulls(jsonb_build_object(
          'presence',      case when p.presence_visibility      <> 'everyone' then p.presence_visibility      end,
          'last_seen',     case when p.last_seen_visibility     <> 'everyone' then p.last_seen_visibility     end,
          'profile_photo', case when p.profile_photo_visibility <> 'everyone' then p.profile_photo_visibility end,
          'about',         case when p.about_visibility         <> 'everyone' then p.about_visibility         end,
          'story',         case when p.story_visibility         <> 'everyone' then p.story_visibility         end,
          'leaderboard',   case when p.leaderboard_visibility   <> 'everyone' then p.leaderboard_visibility   end
          ,'call',        case when p.call_visibility        <> 'everyone' then p.call_visibility        end
        ))
      ) order by p.nickname), '[]'::jsonb)
      from public.profiles p
     where not (p.id = any(v_excl))
       and not (p.id = any(v_dummy))
       and coalesce(p.needs_onboarding, false) = false
       and (p.presence_visibility       <> 'everyone'
         or p.last_seen_visibility      <> 'everyone'
         or p.profile_photo_visibility  <> 'everyone'
         or p.about_visibility          <> 'everyone'
         or p.story_visibility          <> 'everyone'
         or p.leaderboard_visibility    <> 'everyone'
         or p.call_visibility           <> 'everyone')),
    'points_enabled', (select points_enabled from app_settings where id = 'global'),
    -- ── Versi aplikasi (per INSTALL/device, exclude admin/dev) ──
    'app_versions', coalesce((
      select jsonb_agg(
        jsonb_build_object('version', v.version, 'devices', v.devices)
        order by v.semver desc)
      from (
        select
          d.app_version as version,
          count(*)::int as devices,
          (split_part(d.app_version, '.', 1))::int * 10000
          + coalesce(nullif(split_part(d.app_version, '.', 2), '')::int, 0) * 100
          + coalesce(nullif(split_part(d.app_version, '.', 3), '')::int, 0) as semver
        from public.user_devices d
        where d.app_version <> ''
          and d.app_version !~ '-'
          and d.app_version ~ '^[0-9]+\.[0-9]+'
          and not (d.user_id = any(v_excl))
          and not (d.user_id = any(v_dummy))
        group by 1
        order by 3 desc, 2 desc
        limit 10
      ) v
    ), '[]'::jsonb),
    'app_version_count', (select count(*) from public.user_devices d
      where d.app_version <> ''
        and d.app_version !~ '-'
        and d.app_version ~ '^[0-9]+\.[0-9]+'
        and not (d.user_id = any(v_excl))
        and not (d.user_id = any(v_dummy))),
    'app_version_avg_scaled', (
      select round(avg(
        (split_part(d.app_version, '.', 1))::int * 10000
        + coalesce(nullif(split_part(d.app_version, '.', 2), '')::int, 0) * 100
        + coalesce(nullif(split_part(d.app_version, '.', 3), '')::int, 0)
      ))::int
      from public.user_devices d
      where d.app_version <> ''
        and d.app_version !~ '-'
        and d.app_version ~ '^[0-9]+\.[0-9]+'
        and not (d.user_id = any(v_excl))
        and not (d.user_id = any(v_dummy))
    )
  ) into result;
  return result;
end;
$function$

-- snapshot-fn: admin_stats_detail
CREATE OR REPLACE FUNCTION public.admin_stats_detail()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_dummy))), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last)
      from profiles where is_registered = true
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'location_mocked', location_mocked, 'mock_reason', location_mock_reason,
        'excluded', (id = any(v_excl))
      ) order by last_seen desc nulls last)
      from profiles where is_registered = false
        and not (id = any(v_dummy))), '[]'::jsonb),
    'rooms_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'room_id', t.room_id,
        'room_name', coalesce(r.name, t.room_id),
        'is_private', coalesce(r.is_private, false),
        'user_count', t.c
      ) order by t.c desc)
      from (select room_id, count(*) as c from room_presence group by room_id) t
      left join rooms r on r.id = t.room_id), '[]'::jsonb),
    'messages_today', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'sender_id', sender_id,
          'sender_name', sender_name,
          'sender_gender', sender_gender,
          'text', case when type = 'image' then '[foto]' else text end,
          'type', type,
          'created_at', created_at
        ) as x
        from private_messages
        where created_at >= current_date at time zone 'Asia/Jakarta'
        order by created_at desc
        limit 200
      ) sub), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$

-- snapshot-fn: admin_stats_force
CREATE OR REPLACE FUNCTION public.admin_stats_force()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_data jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  v_data := public.admin_stats_compute();
  update public.admin_stats_cache
     set data = v_data, refreshed_at = now()
   where id = 1;
  return jsonb_set(v_data, '{refreshed_at}', to_jsonb(now()));
end;
$function$

-- snapshot-fn: admin_stats_users_page
CREATE OR REPLACE FUNCTION public.admin_stats_users_page(p_kind text DEFAULT 'all'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_kind not in ('all','active','registered','anonymous') then
    p_kind := 'all';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  with base as (
    select p.*
      from public.profiles p
     where not (p.id = any(v_dummy))
       and not (p.id = any(v_excl))
       and not (coalesce(p.needs_onboarding, false) and not coalesce(p.is_registered, false))
       and case p_kind
             when 'active' then
               p.last_seen >= current_date at time zone 'Asia/Jakarta'
             when 'registered' then p.is_registered = true
             when 'anonymous' then coalesce(p.is_registered, false) = false
             else true
           end
  ),
  counted as (select count(*) as total from base),
  page as (
    select b.*
      from base b
     order by b.created_at desc nulls last, b.id
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select total from counted),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status, 'email', email,
        'is_registered', is_registered, 'last_seen', last_seen,
        'created_at', created_at,
        'lat', lat, 'lon', lon, 'loc_source', loc_source,
        'excluded', (id = any(v_excl))
      ) order by created_at desc nulls last, id)
      from page
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$

-- snapshot-fn: admin_storage_stats
CREATE OR REPLACE FUNCTION public.admin_storage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_db bigint;
  v_total_files bigint;
  v_total_bytes bigint;
  v_msg_day bigint; v_msg_week bigint; v_msg_month bigint;
  v_sig_day bigint; v_sig_week bigint; v_sig_month bigint;
  v_stor_day bigint; v_stor_week bigint; v_stor_month bigint;
  v_reg_day bigint; v_reg_week bigint; v_reg_month bigint;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select pg_database_size(current_database()) into v_db;

  select coalesce(count(*),0), coalesce(sum((metadata->>'size')::bigint),0)
    into v_total_files, v_total_bytes
    from storage.objects;

  -- Pertumbuhan pesan privat (teks + gambar base64).
  select coalesce(sum(length(coalesce(text,'')) + length(coalesce(image_data,''))),0)
    into v_msg_day from private_messages where created_at > now() - interval '1 day';
  select coalesce(sum(length(coalesce(text,'')) + length(coalesce(image_data,''))),0)
    into v_msg_week from private_messages where created_at > now() - interval '7 days';
  select coalesce(sum(length(coalesce(text,'')) + length(coalesce(image_data,''))),0)
    into v_msg_month from private_messages where created_at > now() - interval '30 days';

  -- Pertumbuhan sinyal call (payload JSON).
  select coalesce(sum(octet_length(payload::text)),0) into v_sig_day
    from call_signals where created_at > now() - interval '1 day';
  select coalesce(sum(octet_length(payload::text)),0) into v_sig_week
    from call_signals where created_at > now() - interval '7 days';
  select coalesce(sum(octet_length(payload::text)),0) into v_sig_month
    from call_signals where created_at > now() - interval '30 days';

  -- Pertumbuhan file storage.
  select coalesce(sum((metadata->>'size')::bigint),0) into v_stor_day
    from storage.objects where created_at > now() - interval '1 day';
  select coalesce(sum((metadata->>'size')::bigint),0) into v_stor_week
    from storage.objects where created_at > now() - interval '7 days';
  select coalesce(sum((metadata->>'size')::bigint),0) into v_stor_month
    from storage.objects where created_at > now() - interval '30 days';

  -- Pertumbuhan registrasi email.
  select count(*) into v_reg_day from profiles
   where is_registered = true and created_at > now() - interval '1 day';
  select count(*) into v_reg_week from profiles
   where is_registered = true and created_at > now() - interval '7 days';
  select count(*) into v_reg_month from profiles
   where is_registered = true and created_at > now() - interval '30 days';

  select jsonb_build_object(
    'db_bytes',            v_db,
    'storage_bytes',       v_total_bytes,
    'storage_files',       v_total_files,
    'total_bytes',         v_db + v_total_bytes,
    'quota_db_bytes',      8589934592,       -- 8 GB (paket PRO)
    'quota_storage_bytes', 107374182400,     -- 100 GB (paket PRO)
    'quota_bandwidth_bytes', 268435456000,   -- 250 GB egress (paket PRO)
    'plan',                'pro',
    'growth', jsonb_build_object(
      'day',   jsonb_build_object('messages', v_msg_day,  'signals', v_sig_day,  'storage', v_stor_day,  'registrations', v_reg_day),
      'week',  jsonb_build_object('messages', v_msg_week, 'signals', v_sig_week, 'storage', v_stor_week, 'registrations', v_reg_week),
      'month', jsonb_build_object('messages', v_msg_month,'signals', v_sig_month,'storage', v_stor_month,'registrations', v_reg_month)
    )
  ) into result;

  return result;
end;
$function$

-- snapshot-fn: admin_story_all (overload 1)
CREATE OR REPLACE FUNCTION public.admin_story_all(p_limit integer DEFAULT 200, p_filter text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'author_id', s.author_id,
    'author_name', s.author_name,
    'author_avatar', case
        when public.privacy_can_view(s.author_id, 'profile_photo', auth.uid())
        then coalesce((select avatar from public.profiles p where p.id = s.author_id), '')
        else '' end,
    'image_path', s.image_path,
    'media_type', s.media_type,
    'video_path', s.video_path,
    'duration_ms', s.duration_ms,
    'owner_only', s.owner_only,
    'visibility', s.visibility,
    'like_count', (select count(*) from public.story_likes l where l.story_id = s.id),
    'created_at', s.created_at,
    'expires_at', s.expires_at
  ) order by s.created_at desc), '[]'::jsonb)
  into result
  from (
    select * from public.stories s
    where s.expires_at > now()
      and (
        coalesce(p_filter, 'all') = 'all'
        or (p_filter = 'private'   and s.owner_only)
        or (p_filter = 'public'    and not s.owner_only and s.visibility = 'everyone')
        or (p_filter = 'followers' and not s.owner_only and s.visibility = 'followers')
        or (p_filter = 'friends'   and not s.owner_only and s.visibility = 'friends')
      )
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  ) s;
  return result;
end;
$function$

-- snapshot-fn: admin_story_all (overload 2)
CREATE OR REPLACE FUNCTION public.admin_story_all(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'author_id', s.author_id,
    'author_name', s.author_name,
    'image_path', s.image_path,
    'media_type', s.media_type,
    'owner_only', s.owner_only,
    'visibility', s.visibility,
    'created_at', s.created_at,
    'expires_at', s.expires_at
  ) order by s.created_at desc), '[]'::jsonb)
  into result
  from (
    select * from public.stories
    where expires_at > now()
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  ) s;
  return result;
end;
$function$

-- snapshot-fn: admin_story_delete
CREATE OR REPLACE FUNCTION public.admin_story_delete(p_story_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_path text;
  v_video text;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select image_path, coalesce(video_path, '')
    into v_path, v_video
  from public.stories where id = p_story_id;
  if v_path is null then
    raise exception 'Story tidak ditemukan';
  end if;
  delete from public.stories where id = p_story_id;
  return jsonb_build_object('ok', true, 'image_path', v_path, 'video_path', v_video);
end;
$function$

-- snapshot-fn: admin_sweep_calls
CREATE OR REPLACE FUNCTION public.admin_sweep_calls()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ringing int;
  v_answered int;
  v_signals int;
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'zunixe@gmail.com'
     and auth.role() <> 'service_role' then
    raise exception 'Unauthorized';
  end if;

  -- Ringing tak pernah dijawab > 90 detik
  update public.calls
     set status = 'missed', ended_at = now()
   where status = 'ringing'
     and created_at < now() - interval '90 seconds';
  get diagnostics v_ringing = row_count;

  -- Answered tapi heartbeat mati > 75 detik (app ditutup paksa / crash)
  update public.calls
     set status = 'ended', ended_at = now()
   where status = 'answered'
     and ended_at is null
     and coalesce(last_seen_at, answered_at, created_at) < now() - interval '75 seconds';
  get diagnostics v_answered = row_count;

  -- Sinyal call yang sudah berakhir > 1 jam tidak berguna lagi —
  -- tanpa ini tabel call_signals membengkak dan memperlambat realtime.
  delete from public.call_signals s
   using public.calls c
   where s.call_id = c.id
     and c.status in ('ended','missed','canceled','declined')
     and c.ended_at is not null
     and c.ended_at < now() - interval '1 hour';
  get diagnostics v_signals = row_count;

  return v_ringing + v_answered + v_signals;
end;
$function$

-- snapshot-fn: admin_table_sizes
CREATE OR REPLACE FUNCTION public.admin_table_sizes(p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_db bigint;
  v_lim int := greatest(coalesce(p_limit, 30), 1);
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select pg_database_size(current_database()) into v_db;

  select jsonb_build_object(
    'db_bytes', v_db,
    'tables', coalesce((
      select jsonb_agg(t)
      from (
        select jsonb_build_object(
          'schema', n.nspname,
          'table', c.relname,
          'total_bytes', pg_total_relation_size(c.oid),
          'table_bytes', pg_relation_size(c.oid),
          'index_bytes', pg_indexes_size(c.oid),
          'rows_est', c.reltuples::bigint
        ) as t
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where c.relkind in ('r', 'p')
          and n.nspname not in ('pg_catalog', 'information_schema')
        order by pg_total_relation_size(c.oid) desc
        limit v_lim
      ) s
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$

-- snapshot-fn: admin_test
CREATE OR REPLACE FUNCTION public.admin_test(p_chat_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'chat_id',m.chat_id,'sender_id',m.sender_id,'sender_name',m.sender_name,'text',m.text,'type',m.type,'created_at',m.created_at) order by m.created_at desc),'[]'::jsonb) into result from private_messages m where m.chat_id=p_chat_id order by m.created_at desc limit 5;
    return result;
    end;$function$

-- snapshot-fn: admin_timeline_all
CREATE OR REPLACE FUNCTION public.admin_timeline_all(p_limit integer DEFAULT 100, p_filter text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'author_id', p.author_id,
    'author_name', p.author_name,
    'author_gender', p.author_gender,
    'text', p.text,
    'image_path', p.image_path,
    'visibility', p.visibility,
    'like_count', p.like_count,
    'comment_count', p.comment_count,
    'share_count', p.share_count,
    'is_boosted', p.is_boosted,
    'created_at', p.created_at
  ) order by p.created_at desc), '[]'::jsonb)
  into result
  from (
    select * from public.posts
    where coalesce(p_filter, 'all') = 'all'
       or visibility = p_filter
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) p;
  return result;
end;
$function$

-- snapshot-fn: admin_toggle_points
CREATE OR REPLACE FUNCTION public.admin_toggle_points(enabled boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update app_settings
  set points_enabled = enabled, updated_at = now()
  where id = 'global';

  return enabled;
end;
$function$

-- snapshot-fn: admin_update_dummy_profile
CREATE OR REPLACE FUNCTION public.admin_update_dummy_profile(p_uid uuid, p_nickname text, p_gender text, p_age integer, p_country text, p_city text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if not public.is_admin_request() then raise exception 'Unauthorized [email=% uid=% role=%]', coalesce(auth.email(),'NULL'), coalesce(auth.uid()::text,'NULL'), coalesce(auth.role(),'NULL'); end if; if p_gender not in ('male','female') then raise exception 'Gender tidak valid'; end if; if p_age < 18 or p_age > 80 then raise exception 'Umur tidak valid'; end if; if length(trim(p_nickname)) < 3 or length(p_nickname) > 20 then raise exception 'Nickname harus 3-20 karakter'; end if; update public.profiles set nickname=p_nickname, gender=p_gender, age=p_age, country=p_country, city=p_city, last_seen=now() where id=p_uid; update public.dummy_accounts set nickname=p_nickname where uid=p_uid; return jsonb_build_object('ok',true); end; $function$

-- snapshot-fn: admin_update_dummy_token
CREATE OR REPLACE FUNCTION public.admin_update_dummy_token(p_uid uuid, p_refresh_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role'
     and auth.uid() != p_uid then
    raise exception 'Unauthorized';
  end if;
  update public.dummy_accounts set refresh_token = p_refresh_token where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: admin_update_point_settings
CREATE OR REPLACE FUNCTION public.admin_update_point_settings(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    -- Foto
    photo_upload_reward    = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once      = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm      = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct = coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    -- Bonus lama (dipertahankan agar form tidak error; faucet sudah no-op)
    bonus_registered       = coalesce((p->>'bonus_registered')::int, bonus_registered),
    bonus_rated            = coalesce((p->>'bonus_rated')::int, bonus_rated),
    bonus_shared           = coalesce((p->>'bonus_shared')::int, bonus_shared),
    bonus_profile          = coalesce((p->>'bonus_profile')::int, bonus_profile),
    bonus_first_photo      = coalesce((p->>'bonus_first_photo')::int, bonus_first_photo),
    bonus_room_read        = coalesce((p->>'bonus_room_read')::int, bonus_room_read),
    bonus_new_chat         = coalesce((p->>'bonus_new_chat')::int, bonus_new_chat),
    bonus_invited          = coalesce((p->>'bonus_invited')::int, bonus_invited),
    bonus_first_room       = coalesce((p->>'bonus_first_room')::int, bonus_first_room),
    bonus_referral         = coalesce((p->>'bonus_referral')::int, bonus_referral),
    bonus_online_5min      = coalesce((p->>'bonus_online_5min')::int, bonus_online_5min),
    bonus_online_30min     = coalesce((p->>'bonus_online_30min')::int, bonus_online_30min),
    bonus_online_60min     = coalesce((p->>'bonus_online_60min')::int, bonus_online_60min),
    bonus_online_120min    = coalesce((p->>'bonus_online_120min')::int, bonus_online_120min),
    bonus_price_multiplier = coalesce((p->>'bonus_price_multiplier')::int, bonus_price_multiplier),
    -- Tarif call BARU
    call_audio_cost_per_min = coalesce((p->>'call_audio_cost_per_min')::int, call_audio_cost_per_min),
    call_video_cost_per_min = coalesce((p->>'call_video_cost_per_min')::int, call_video_cost_per_min),
    call_free_minutes_daily = coalesce((p->>'call_free_minutes_daily')::int, call_free_minutes_daily),
    call_cut_pct            = coalesce((p->>'call_cut_pct')::int, call_cut_pct),
    -- Fitur berbayar lain
    filter_gender_cost      = coalesce((p->>'filter_gender_cost')::int, filter_gender_cost),
    nearby_cost             = coalesce((p->>'nearby_cost')::int, nearby_cost),
    -- Room
    room_create_paid        = coalesce((p->>'room_create_paid')::int, room_create_paid),
    room_create_pw_paid     = coalesce((p->>'room_create_pw_paid')::int, room_create_pw_paid),
    room_join_paid          = coalesce((p->>'room_join_paid')::int, room_join_paid),
    room_extend_paid        = coalesce((p->>'room_extend_paid')::int, room_extend_paid),
    room_reads_daily_limit  = coalesce((p->>'room_reads_daily_limit')::int, room_reads_daily_limit),
    new_chats_daily_limit   = coalesce((p->>'new_chats_daily_limit')::int, new_chats_daily_limit),
    subscribe_cut_pct       = coalesce((p->>'subscribe_cut_pct')::int, subscribe_cut_pct),
    subscription_duration_days = coalesce((p->>'subscription_duration_days')::int, subscription_duration_days),
    -- Biaya chat
    cost_chat_text          = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image         = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once          = coalesce((p->>'cost_view_once')::int, cost_view_once),
    -- Share / reengage
    share_url               = coalesce(p->>'share_url', share_url),
    share_click_reward      = coalesce((p->>'share_click_reward')::int, share_click_reward),
    share_click_cap_daily   = coalesce((p->>'share_click_cap_daily')::int, share_click_cap_daily),
    reengage_enabled        = coalesce((p->>'reengage_enabled')::boolean, reengage_enabled),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $function$

-- snapshot-fn: admin_user_detail
CREATE OR REPLACE FUNCTION public.admin_user_detail(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id',        pr.id,
      'nickname',       pr.nickname,
      'gender',         pr.gender,
      'age',            pr.age,
      'country',        pr.country,
      'city',           pr.city,
      'email',          pr.email,
      'is_registered',  pr.is_registered,
      'status',         pr.status,
      'points',         pr.points,
      'ip_address',     pr.ip_address,
      'login_at',       pr.login_at,
      'last_seen',      pr.last_seen,
      'created_at',     pr.created_at,
      'is_dummy',       exists (select 1 from public.dummy_accounts du where du.uid = pr.id)
    ),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'install_id',   d.install_id,
        'brand',        d.brand,
        'model',        d.model,
        'os_name',      d.os_name,
        'os_version',   d.os_version,
        'app_version',  d.app_version,
        'ip_address',   d.ip_address,
        'last_seen_at', d.last_seen_at,
        'is_active',    d.is_active,
        'created_at',   d.created_at
      ) order by d.last_seen_at desc nulls last)
      from public.user_devices d where d.user_id = p_uid
    ), '[]'::jsonb),
    'chats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'chat_id', c.chat_id,
        'participant_names', c.participant_names,
        'participants', c.participants,
        'last_message', c.last_message,
        'last_message_at', c.last_message_at,
        'message_count', coalesce(m.msg_count, 0)
      ) order by c.last_message_at desc nulls last)
      from public.private_chats c
      -- SATU agregasi (ganti count(*) per chat).
      left join (
        select m.chat_id as chat_id, count(*) as msg_count
          from public.private_messages m
         where m.chat_id in (
           select c2.chat_id from public.private_chats c2
           where c2.participants @> array[p_uid]::uuid[]
         )
         group by m.chat_id
      ) m on m.chat_id = c.chat_id
      where c.participants @> array[p_uid]::uuid[]
    ), '[]'::jsonb),
    -- DIBATASI 200 terbaru (dulu tanpa limit).
    'location_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lat', h.lat,
        'lon', h.lon,
        'source', h.loc_source,
        'at', h.created_at,
        'mocked', h.location_mocked,
        'reason', h.mock_reason,
        'accuracy_m', h.accuracy_m
      ) order by h.created_at desc)
      from (
        select h2.lat, h2.lon, h2.loc_source, h2.created_at,
               h2.location_mocked, h2.mock_reason, h2.accuracy_m
          from public.user_location_history h2
         where h2.user_id = p_uid
         order by h2.created_at desc
         limit 200
      ) h
    ), '[]'::jsonb)
  ) into result
  from public.profiles pr
  where pr.id = p_uid;

  return result;
end;
$function$

-- snapshot-fn: admin_wake_dummy
CREATE OR REPLACE FUNCTION public.admin_wake_dummy(p_uid uuid, p_minutes integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_until timestamptz;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  v_until := now() + make_interval(mins => least(greatest(coalesce(p_minutes, 10), 1), 120));
  update public.dummy_accounts
     set ai_wake_until = v_until
   where uid = p_uid;
  update public.profiles
     set status = 'online', last_seen = now()
   where id = p_uid and status <> 'invisible';
  return jsonb_build_object('uid', p_uid, 'wake_until', v_until);
end;
$function$

-- snapshot-fn: admin_withdrawal_list
CREATE OR REPLACE FUNCTION public.admin_withdrawal_list(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select w.id, w.user_id, w.coin_amount, w.payout_idr, w.rate, w.status,
           w.pay_method, w.pay_account, w.pay_holder, w.admin_note, w.tx_id,
           w.created_at, w.reviewed_at, p.nickname, p.email
    from withdrawal_requests w
    join profiles p on p.id = w.user_id
    where (p_status = 'all' or w.status = p_status)
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: admin_withdrawal_review
CREATE OR REPLACE FUNCTION public.admin_withdrawal_review(p_request_id uuid, p_action text, p_note text DEFAULT NULL::text, p_tx_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); w record;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then raise exception 'Unauthorized'; end if;

  select * into w from withdrawal_requests where id = p_request_id;
  if not found then raise exception 'Request not found'; end if;
  if w.status <> 'pending' then raise exception 'Already reviewed'; end if;

  if p_action = 'pay' then
    update withdrawal_requests set status = 'paid', tx_id = p_tx_id,
      admin_note = p_note, reviewed_by = uid, reviewed_at = now(), updated_at = now()
      where id = p_request_id;
    insert into public.point_events (user_id, event, amount, metadata)
      values (w.user_id, 'withdraw_paid', -w.coin_amount,
              jsonb_build_object('request', w.id, 'payout_idr', w.payout_idr, 'tx', p_tx_id));
  elsif p_action = 'reject' then
    update withdrawal_requests set status = 'rejected', admin_note = p_note,
      reviewed_by = uid, reviewed_at = now(), updated_at = now()
      where id = p_request_id;
    -- refund earned
    perform public.ledger_credit(w.user_id, 'earned', 'withdraw_refund', w.coin_amount,
      w.id::text, jsonb_build_object('request', w.id));
    perform public.wallet_sync_points(w.user_id);
    insert into public.point_events (user_id, event, amount, metadata)
      values (w.user_id, 'withdraw_refund', w.coin_amount,
              jsonb_build_object('request', w.id));
  else
    raise exception 'Invalid action';
  end if;

  return jsonb_build_object('ok', true, 'status', p_action);
end; $function$

-- snapshot-fn: ai_log_reply
CREATE OR REPLACE FUNCTION public.ai_log_reply(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean, p_stage text, p_decision text, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Noise filter: dua gate ini tidak lagi dicatat (sinyalnya ada di
  -- dummy_accounts.ai_enabled). Semua decision lain tetap tercatat.
  if p_decision in ('skipped:dummy_disabled', 'skipped:ai_disabled') then
    return;
  end if;

  insert into public.ai_reply_log(chat_id, trigger_msg_id, sender_id, dummy_uid, proactive, stage, decision, detail)
  values (p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, coalesce(p_proactive, false), p_stage, p_decision, coalesce(p_detail, '{}'::jsonb));
exception when others then
  null;
end;
$function$

-- snapshot-fn: ai_memory_cleanup
CREATE OR REPLACE FUNCTION public.ai_memory_cleanup()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.ai_memory
  where created_at < now() - interval '30 days';
end;
$function$

-- snapshot-fn: ai_presence_tick
CREATE OR REPLACE FUNCTION public.ai_presence_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d record;
  v_hour int;
  v_active bool;
  v_wake bool;
begin
  v_hour := extract(hour from (now() + interval '7 hours'))::int;

  for d in
    select da.uid, da.ai_active_hours, da.ai_offline_until, da.ai_wake_until,
           da.ai_always_online, p.status as cur_status
    from public.dummy_accounts da
    join public.profiles p on p.id = da.uid
    where da.ai_enabled = true
  loop
    begin
      -- Invisible manual (set dari admin panel) — cron tidak boleh
      -- menimpa (baik membangunkan saat jam aktif maupun meng-offline-kan
      -- di luar jam). AI tetap membalas; presence-wake ai-reply juga
      -- mempertahankan status ini (cabang else = refresh last_seen saja).
      if d.cur_status = 'invisible' then
        continue;
      end if;
      -- ── BANGUNKAN SEMENTARA (admin_wake_dummy): paksa online + segar
      -- sampai ai_wake_until lewat. Mengalahkan jadwal & tidur.
      v_wake := d.ai_wake_until is not null and d.ai_wake_until > now();
      if v_wake then
        if d.cur_status <> 'online' then
          update public.profiles
             set status = 'online', last_seen = now()
           where id = d.uid;
        else
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
        continue;
      end if;
      -- Wake kedaluwarsa → bersihkan sekali (jadwal di bawah mengambil alih).
      if d.ai_wake_until is not null then
        update public.dummy_accounts set ai_wake_until = null where uid = d.uid;
      end if;
      -- ── MODE NGAMBEK (marah pergi) ──
      if d.ai_offline_until is not null and d.ai_offline_until > now() then
        if d.cur_status <> 'offline' then
          update public.profiles
             set status = 'offline', last_seen = now()
           where id = d.uid;
        end if;
        continue; -- abaikan jadwal jam aktif selama ngambek
      end if;
      -- Waktu ngambek habis → bangunkan sesuai jadwal.
      if d.ai_offline_until is not null and d.ai_offline_until <= now() then
        update public.dummy_accounts set ai_offline_until = null, ai_mood = 'normal'
          where uid = d.uid;
        update public.profiles
           set status = (case when v_hour::int = any(
                 select (x::int) from jsonb_array_elements_text(
                   coalesce(d.ai_active_hours, '[]'::jsonb)) as x
                 where x ~ '^[0-9]+$'
               ) then 'online' else 'offline' end),
               last_seen = now()
         where id = d.uid;
        continue;
      end if;

      -- ── SELALU ONLINE (cabang restore 13070000; hanya Admin Chatyuk
      -- yang flag-nya true) — jadwal & idle-drift dilewati: paksa online
      -- + last_seen segar. Dummy lain (false) lewat sini tanpa perubahan.
      if coalesce(d.ai_always_online, false) then
        if d.cur_status <> 'online' then
          update public.profiles
             set status = 'online', last_seen = now()
           where id = d.uid;
        else
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
        continue;
      end if;

      -- Jadwal belum diatur → jangan sentuh presence (mode manual).
      if d.ai_active_hours is null or
         jsonb_array_length(d.ai_active_hours) = 0 then
        continue;
      end if;

      -- Hanya elemen numerik yang dipakai (array korup tidak boleh
      -- menggagalkan tick untuk dummy lain).
      v_active := (v_hour::int = any(
        select (x::int)
        from jsonb_array_elements_text(d.ai_active_hours) as x
        where x ~ '^[0-9]+$'
      ));

      if v_active and d.cur_status = 'offline' then
        update public.profiles
           set status = 'online', last_seen = now()
         where id = d.uid;
      elsif v_active and d.cur_status = 'online' then
        -- Kadang melamun seperti user mendiamkan app: 30%/tick → idle.
        if random() < 0.30 then
          update public.profiles
             set status = 'idle', last_seen = now()
           where id = d.uid;
        else
          -- Jaga last_seen segar supaya tetap muncul di daftar online (window 30m).
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
      elsif v_active and d.cur_status = 'idle' then
        -- Kembali pegang HP: 50%/tick → online. last_seen selalu segar
        -- supaya idle tetap tampil di daftar online.
        if random() < 0.50 then
          update public.profiles
             set status = 'online', last_seen = now()
           where id = d.uid;
        else
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
      elsif not v_active and d.cur_status <> 'offline' then
        update public.profiles set status = 'offline' where id = d.uid;
      end if;
    exception when others then
      -- Satu dummy bermasalah tidak boleh menghentikan tick dummy lain.
      continue;
    end;
  end loop;
end;
$function$

-- snapshot-fn: ai_proactive_tick
CREATE OR REPLACE FUNCTION public.ai_proactive_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r record;
  v_n int := 0;
begin
  if exists (
    select 1 from public.app_settings
    where id = 'global' and ai_global_enabled = false
  ) then
    return jsonb_build_object('ok', true, 'nudged', 0, 'skipped', 'global_off');
  end if;

  -- Tombol AI↔AI OFF: jangan pernah menyapa di chat yang SEMUA pesertanya
  -- dummy. Menyapa di chat dummy×dummy = menghidupkan kembali AI↔AI yang
  -- sudah dimatikan owner (lewat jalur proactive yang bypass trigger).
  if exists (
    select 1 from public.app_settings
    where id = 'global' and coalesce(ai_ai_chat_enabled, true) = false
  ) then
    return jsonb_build_object('ok', true, 'nudged', 0, 'skipped', 'ai_ai_off');
  end if;

  for r in
    select pc.chat_id,
           (select m.sender_id
              from public.private_messages m
             where m.chat_id = pc.chat_id
             order by m.created_at desc limit 1) as last_sender,
           (select max(m.created_at)
              from public.private_messages m
             where m.chat_id = pc.chat_id) as last_at,
           d.uid as dummy_uid
      from public.private_chats pc
      join public.dummy_accounts d
        on d.uid = any (pc.participants) and d.ai_enabled = true
      where coalesce(d.ai_hold_active, false) = false
        -- Chat dummy×dummy hanya diproses bila tombol AI↔AI ON.
        and (
          coalesce(
            (select s.ai_ai_chat_enabled from public.app_settings s
              where s.id = 'global'), true
          )
          or not exists (
            select 1 from unnest(pc.participants) as p
            where not exists (
              select 1 from public.dummy_accounts dd where dd.uid = p
            )
          )
        )
  loop
    begin
      -- Hanya jika pesan terakhir dari MANUSIA (bukan dummy mana pun)
      if r.last_sender is null then continue; end if;
      if exists (
        select 1 from public.dummy_accounts d2 where d2.uid = r.last_sender
      ) then continue; end if;
      -- Hening >45 menit
      if r.last_at is null or r.last_at > now() - interval '45 minutes' then
        continue;
      end if;
      -- Cooldown 3 jam per chat
      if exists (
        select 1 from public.ai_chat_state s
        where s.chat_id = r.chat_id
          and s.proactive_at > now() - interval '3 hours'
      ) then continue; end if;

      insert into public.ai_chat_state (chat_id, proactive_at, updated_at)
      values (r.chat_id, now(), now())
      on conflict (chat_id) do update
        set proactive_at = now(), updated_at = now();

      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-reply',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'chat_id', r.chat_id,
          'trigger_msg_id', null,
          'sender_id', r.last_sender,
          'dummy_uid', r.dummy_uid,
          'proactive', true
        )
      );
      v_n := v_n + 1;
    exception when others then
      null;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'nudged', v_n);
end;
$function$

-- snapshot-fn: ai_reply_claim
CREATE OR REPLACE FUNCTION public.ai_reply_claim(p_msg_id bigint, p_dummy uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  delete from public.ai_reply_claims where claimed_at < now() - interval '1 hour';
  begin
    insert into public.ai_reply_claims (trigger_msg_id, dummy_uid)
    values (p_msg_id, p_dummy);
    return true;
  exception when unique_violation then
    return false;
  end;
end;
$function$

-- snapshot-fn: ai_reply_claim_recovery
CREATE OR REPLACE FUNCTION public.ai_reply_claim_recovery()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r record;
begin
  for r in
    select c.trigger_msg_id, c.dummy_uid, m.chat_id, m.sender_id
    from public.ai_reply_claims c
    join public.private_messages m on m.id = c.trigger_msg_id
    where c.claimed_at < now() - interval '10 minutes'
      and c.claimed_at > now() - interval '1 hour'
      and not exists (
        select 1 from public.private_messages m2
        where m2.chat_id = m.chat_id
          and m2.sender_id = c.dummy_uid
          and m2.id > c.trigger_msg_id
      )
  loop
    begin
      -- Helper terpusat: URL + x-app-secret dari ai_internal_config.
      perform public.ai_reply_post(
        r.chat_id, r.trigger_msg_id, r.sender_id, r.dummy_uid, false
      );
      delete from public.ai_reply_claims
        where trigger_msg_id = r.trigger_msg_id;
    exception when others then
      null;
    end;
  end loop;
  delete from public.ai_reply_claims
    where claimed_at < now() - interval '1 hour';
end;
$function$

-- snapshot-fn: ai_reply_enqueue
CREATE OR REPLACE FUNCTION public.ai_reply_enqueue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_other uuid;
  v_no_rate boolean;
  v_always_reply boolean;
  v_sender_no_rate boolean;
  v_sender_is_dummy boolean;
  v_global boolean;
  v_ai_ai_on boolean;
  v_max int;
  v_min int;
  v_gmax int;
  v_gmin int;
  v_dummy_out_1h int;
  v_last_dummy_out timestamptz;
  v_ai_ai_1h int;
begin
  if coalesce(new.type, 'text') != 'text' then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null,
      false, 'enqueue', 'skipped:non_text', '{}');
    return new;
  end if;

  select x into v_other
  from unnest((select pc.participants
               from public.private_chats pc
               where pc.chat_id = new.chat_id)) as x
  where x <> new.sender_id
  limit 1;
  if v_other is null then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null,
      false, 'enqueue', 'skipped:no_other', '{}');
    return new;
  end if;

  select d.ai_no_rate_limit, d.ai_always_reply, d.ai_max_replies,
         d.ai_min_interval
    into v_no_rate, v_always_reply, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if not found then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other,
      false, 'enqueue', 'skipped:dummy_disabled', '{}');
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour,
         s.ai_min_interval_sec, coalesce(s.ai_ai_chat_enabled, true)
    into v_global, v_gmax, v_gmin, v_ai_ai_on
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other,
      false, 'enqueue', 'skipped:global_off', '{}');
    return new;
  end if;

  if v_sender_is_dummy and not coalesce(v_ai_ai_on, true) then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other,
      false, 'enqueue', 'skipped:ai_ai_off', '{}');
    return new;
  end if;

  if coalesce(v_always_reply, false) then
    perform public.ai_reply_post(new.chat_id, new.id, new.sender_id,
      v_other, false);
    return new;
  end if;

  v_max := coalesce(v_max, v_gmax, 30);
  v_min := coalesce(v_min, v_gmin, 5);

  if v_sender_is_dummy then
    select coalesce(d.ai_no_rate_limit, false) into v_sender_no_rate
    from public.dummy_accounts d where d.uid = new.sender_id;
    if not (coalesce(v_no_rate, false) and coalesce(v_sender_no_rate, false)) then
      select count(*) into v_ai_ai_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id in (v_other, new.sender_id)
        and m.created_at > now() - interval '1 hour';
      if v_ai_ai_1h >= 40 then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id,
          v_other, false, 'enqueue', 'skipped:ai_ai_cap', '{}');
        return new;
      end if;
    end if;
  else
    if not coalesce(v_no_rate, false) then
      select count(*) into v_dummy_out_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other
        and m.created_at > now() - interval '1 hour';
      if v_dummy_out_1h >= v_max then
        -- Always-online dummy tidak boleh diturunkan ke idle.
        begin
          begin
            perform 1 from public.dummy_accounts
            where uid = v_other and coalesce(ai_always_online, false) = true;
            if not found then
              update public.profiles
              set status = 'idle', last_seen = now()
              where id = v_other and status = 'online';
            end if;
          exception when undefined_column then
            update public.profiles
            set status = 'idle', last_seen = now()
            where id = v_other and status = 'online';
          end;
        exception when others then
          null;
        end;
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id,
          v_other, false, 'enqueue', 'skipped:rate_max',
          jsonb_build_object('out_1h', v_dummy_out_1h, 'max', v_max));
        return new;
      end if;

      select max(m.created_at) into v_last_dummy_out
      from public.private_messages m
      where m.chat_id = new.chat_id and m.sender_id = v_other;
      if v_last_dummy_out is not null
         and v_last_dummy_out > now() - make_interval(secs => v_min) then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id,
          v_other, false, 'enqueue', 'skipped:rate_min_interval', '{}');
        return new;
      end if;
    end if;
  end if;

  perform public.ai_reply_post(new.chat_id, new.id, new.sender_id,
    v_other, false);
  return new;
end;
$function$

-- snapshot-fn: ai_reply_missed_recovery
CREATE OR REPLACE FUNCTION public.ai_reply_missed_recovery()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r record;
begin
  for r in
    with ranked as (
      select m.id as msg_id,
             m.chat_id,
             m.sender_id,
             (select x
                from unnest(pc.participants) as x
               where x <> m.sender_id
               limit 1) as dummy_uid,
             row_number() over (
               partition by m.chat_id order by m.id desc
             ) as rn
        from public.private_messages m
        join public.private_chats pc on pc.chat_id = m.chat_id
       where m.created_at > now() - interval '20 minutes'
         and m.created_at < now() - interval '4 minutes'
         and coalesce(m.type, 'text') = 'text'
         and not exists (
           select 1 from public.dummy_accounts d
            where d.uid = m.sender_id
         )
         and not exists (
           select 1 from public.ai_reply_claims c
            where c.trigger_msg_id = m.id
         )
    )
    select msg_id, chat_id, sender_id, dummy_uid
      from ranked
     where rn = 1
       and dummy_uid is not null
       and exists (
         select 1 from public.dummy_accounts d
          where d.uid = dummy_uid and d.ai_enabled = true
       )
       and not exists (
         select 1 from public.private_messages m2
          where m2.chat_id = ranked.chat_id
            and m2.id > ranked.msg_id
       )
     limit 20
  loop
    begin
      perform public.ai_reply_post(
        r.chat_id, r.msg_id, r.sender_id, r.dummy_uid, false
      );
    exception when others then
      null;
    end;
  end loop;
end;
$function$

-- snapshot-fn: ai_reply_post
CREATE OR REPLACE FUNCTION public.ai_reply_post(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_url text;
  v_secret text;
begin
  select value into v_url from public.ai_internal_config where key = 'ai_reply_url';
  select value into v_secret from public.ai_internal_config where key = 'callback_secret';
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'skipped:no_secret', '{}');
    return;
  end if;
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-app-secret', v_secret
      ),
      body := jsonb_build_object(
        'chat_id', p_chat_id,
        'trigger_msg_id', p_trigger_msg_id,
        'sender_id', p_sender_id,
        'dummy_uid', p_dummy_uid,
        'proactive', coalesce(p_proactive, false)
      ),
      timeout_milliseconds := 60000
    );
  exception when others then
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'error:post_failed', jsonb_build_object('err', sqlerrm));
    return;
  end;
  perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'enqueued', jsonb_build_object('proactive', coalesce(p_proactive, false)));
end;
$function$

-- snapshot-fn: ai_story_cleanup
CREATE OR REPLACE FUNCTION public.ai_story_cleanup()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Hanya cerita HARI INI (WIB) — hapus bila tipis → regenerate otomatis
  -- pada pesan berikutnya. Cerita hari lampau tetap tersimpan (sejarah).
  delete from public.ai_daily_story
  where story_date = (now() + interval '7 hours')::date
    and coalesce(story->>'work', '') = ''
    and jsonb_array_length(coalesce(story->'activities', '[]'::jsonb)) < 2;
end;
$function$

-- snapshot-fn: approve_join_request
CREATE OR REPLACE FUNCTION public.approve_join_request(p_room_id text, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  actor_role text; cnt int; req_status text;
begin
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role not in ('owner','admin') then raise exception 'Forbidden'; end if;

  select status into req_status from public.room_join_requests
   where room_id = p_room_id and user_id = p_uid;
  if req_status is distinct from 'pending' then raise exception 'No pending request'; end if;

  -- Kapasitas atomik.
  select max_members into cnt from public.rooms where id = p_room_id for update;
  if cnt is null then raise exception 'Room not found'; end if;
  if (select count(*) from public.room_members where room_id = p_room_id) >= cnt then
    raise exception 'Room full';
  end if;

  insert into public.room_members (room_id, user_id, role) values (p_room_id, p_uid, 'member')
    on conflict (room_id, user_id) do nothing;
  update public.room_join_requests
     set status='approved', decided_at=now(), decided_by=auth.uid()
   where room_id = p_room_id and user_id = p_uid;
  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: archive_private_chat
CREATE OR REPLACE FUNCTION public.archive_private_chat(p_chat_id text, p_archive boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  me_text text := me::text;
  r record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into r from public.private_chats where chat_id = p_chat_id;
  if not found then raise exception 'Chat not found'; end if;
  if not exists (select 1 from unnest(r.participants::text[]) as p where p = me_text) then
    raise exception 'Forbidden';
  end if;

  if p_archive then
    update public.private_chats
    set archived_by = array(select distinct unnest(array_append(coalesce(archived_by,'{}'), me_text)))
    where chat_id = p_chat_id;
  else
    update public.private_chats
    set archived_by = array_remove(coalesce(archived_by,'{}'), me_text)
    where chat_id = p_chat_id;
  end if;
  return jsonb_build_object('ok', true, 'archived', p_archive);
end; $function$

-- snapshot-fn: avatar_for
CREATE OR REPLACE FUNCTION public.avatar_for(p_uid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when public.privacy_can_view(p_uid, 'profile_photo', auth.uid())
      then coalesce(p.avatar, '')
    else '' end
  from public.profiles p
  where p.id = p_uid;
$function$

-- snapshot-fn: avatars_for
CREATE OR REPLACE FUNCTION public.avatars_for(p_uids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'avatar', case when public.privacy_can_view(p.id, 'profile_photo', auth.uid())
                   then coalesce(p.avatar, '') else '' end
  )), '[]'::jsonb)
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]));
$function$

-- snapshot-fn: award_share_click
CREATE OR REPLACE FUNCTION public.award_share_click(p_sharer uuid, p_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return jsonb_build_object('ok', true, 'rewarded', false);
end; $function$

-- snapshot-fn: bind_referrer
CREATE OR REPLACE FUNCTION public.bind_referrer(p_referrer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); cur uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_referrer is null or p_referrer = me then
    return jsonb_build_object('ok', false, 'reason', 'invalid_referrer');
  end if;
  if not exists (select 1 from profiles where id = p_referrer) then
    return jsonb_build_object('ok', false, 'reason', 'referrer_not_found');
  end if;

  select referred_by into cur from profiles where id = me;
  if cur is not null then
    return jsonb_build_object('ok', false, 'reason', 'already_bound');
  end if;

  update profiles set referred_by = p_referrer where id = me;
  return jsonb_build_object('ok', true);
end; $function$

-- snapshot-fn: boost_post
CREATE OR REPLACE FUNCTION public.boost_post(p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); p record; points_on boolean;
  paid int; bonus_p int; mult int; hours int; res jsonb; remaining int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into p from public.posts where id = p_post_id;
  if not found then raise exception 'Post not found'; end if;
  if p.author_id <> me then raise exception 'Not author'; end if;
  if p.is_boosted then raise exception 'Already boosted'; end if;

  select points_enabled, cost_post_boost, bonus_price_multiplier, post_boost_hours
    into points_on, paid, mult, hours from public.app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(me, 'post_boost', paid, bonus_p, p_post_id::text);
    remaining := (res->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = me;
  end if;

  update public.posts
    set is_boosted = true, boosted_at = now()
    where id = p_post_id;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0));
end; $function$

-- snapshot-fn: buy_extra_photo_slots_v2
CREATE OR REPLACE FUNCTION public.buy_extra_photo_slots_v2(p_slots integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); cost int; r jsonb; cur int; new_extra int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;
  if p_slots is null or p_slots < 1 or p_slots > 50 then
    raise exception 'Jumlah slot tidak valid';
  end if;

  select cost_extra_photo_slot into cost from app_settings where id = 'global';
  -- Biaya proporsional: 60 untuk 5 slot → 12/slot.
  cost := (cost * p_slots) / 5;

  r := public.spend_yukcoin(me, 'extra_photo_slots', cost, p_slots::text);

  insert into public.photo_slots_unlocked(user_id, extra, updated_at)
    values (me, p_slots, now())
  on conflict (user_id) do update
    set extra = public.photo_slots_unlocked.extra + p_slots,
        updated_at = now()
  returning extra into new_extra;

  return jsonb_build_object('ok', true, 'cost', cost, 'extra', new_extra,
    'remaining', (r->>'remaining')::int);
end; $function$

-- snapshot-fn: buy_ghost_mode_v2
CREATE OR REPLACE FUNCTION public.buy_ghost_mode_v2(p_days integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); cost int; r jsonb; base timestamptz; new_exp timestamptz;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;
  if p_days is null or p_days < 1 or p_days > 30 then
    raise exception 'Durasi tidak valid';
  end if;

  select cost_ghost_mode_daily into cost from app_settings where id = 'global';
  cost := cost * p_days;

  r := public.spend_yukcoin(me, 'ghost_mode', cost, p_days::text);

  -- Perpanjang dari expires_at yang masih berlaku, atau dari now().
  select expires_at into base from public.ghost_mode_active where user_id = me;
  if base is null or base < now() then base := now(); end if;
  new_exp := base + (p_days || ' days')::interval;

  insert into public.ghost_mode_active(user_id, expires_at)
    values (me, new_exp)
  on conflict (user_id) do update set expires_at = excluded.expires_at;

  return jsonb_build_object('ok', true, 'cost', cost,
    'expires_at', new_exp,
    'remaining', (r->>'remaining')::int);
end; $function$

-- snapshot-fn: call_billing_tick
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
end; $function$

-- snapshot-fn: call_free_limit_sec
CREATE OR REPLACE FUNCTION public.call_free_limit_sec()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(call_free_minutes_daily, 5) * 60
    from app_settings where id = 'global';
$function$

-- snapshot-fn: call_history_insert
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
$function$

-- snapshot-fn: call_push (overload 1)
CREATE OR REPLACE FUNCTION public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rec record;
  v_chat_id text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  -- fan-out ke semua token aktif (user_devices + fallback profiles)
  for rec in select public.user_fcm_tokens(p_callee) as fcm_token loop
    insert into public.outbox (type, payload)
    values ('push', jsonb_build_object(
      'token', rec.fcm_token,
      'title', p_name,
      'body', p_call_type,
      'data', jsonb_build_object(
        'type', 'call',
        'callId', p_call,
        'callerUid', p_caller,
        'fromName', p_name,
        'otherName', p_name,
        'callType', p_call_type,
        'chatId', v_chat_id
      )
    ));
  end loop;
end;
$function$

-- snapshot-fn: call_push (overload 2)
CREATE OR REPLACE FUNCTION public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text, p_avatar text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  t text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
  v_chat_id text;
  v_msg text;
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  v_msg := case when p_call_type = 'video' then 'Panggilan video' else 'Panggilan suara' end;
  for t in select public.user_fcm_tokens(p_callee) loop
    insert into public.outbox (type, payload)
    values ('push', jsonb_build_object(
      'token', t,
      'title', p_name,
      'body', v_msg,
      'data', jsonb_build_object(
        'type', 'call',
        'toUid', p_callee,
        'callId', p_call,
        'callerUid', p_caller,
        'fromName', p_name,
        'otherName', p_name,
        'callType', p_call_type,
        'chatId', v_chat_id,
        'avatarUrl', coalesce(p_avatar,''),
        'message', v_msg
      )
    ));
  end loop;
end; $function$

-- snapshot-fn: cancel_friend_request
CREATE OR REPLACE FUNCTION public.cancel_friend_request(p_request_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  req record;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select * into req
    from public.friend_requests
   where id = p_request_id and from_id = me;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- Hanya request PENDING yang bisa dibatalkan. Bila sudah direspons,
  -- biarkan (histori tetap) — bukan hak pengirim membatalkannya.
  if req.status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'not_pending',
                              'status', req.status);
  end if;

  delete from public.friend_requests where id = p_request_id;

  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: charge_metered
CREATE OR REPLACE FUNCTION public.charge_metered(p_caller uuid, p_feature text, p_ref text, p_units integer DEFAULT 1, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cfg jsonb; unit_cost int; cut_pct int;
  total int; cut int; net int; remaining int; balance int;
begin
  -- GUARD KEAMANAN (2026-10-22): user hanya boleh menagih DIRINYA sendiri.
  -- call_billing_tick sudah mengisi p_caller := auth.uid() → tetap jalan.
  if auth.uid() is not null and p_caller is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh menagih user lain'
      using errcode = '42501';
  end if;
  if p_caller is null then raise exception 'Not authenticated'; end if;
  if p_units is null or p_units <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  select metered_pricing -> p_feature into cfg
    from app_settings where id = 'global';
  if cfg is null then
    raise exception 'Unknown metered feature: %', p_feature;
  end if;
  unit_cost := coalesce((cfg->>'unit_cost')::int, 0);
  cut_pct   := coalesce((cfg->>'cut_pct')::int, 0);

  total := unit_cost * p_units;
  if total <= 0 then
    return jsonb_build_object('ok', true, 'charged', 0,
      'remaining', public.yukcoin_total(p_caller));
  end if;

  balance := public.yukcoin_total(p_caller);
  if balance < total then
    raise exception 'YukCoin tidak cukup';
  end if;

  -- Potong dari saldo penelepon (semua bucket boleh dipakai — ekosistem
  -- coin tertutup: coin dari topup & dari income call sama-sama bisa dipakai).
  remaining := public.ledger_spend(p_caller, p_feature, total, p_ref);

  -- Split ke penerima (mis. pemilik call). Platform ambil cut_pct.
  cut := (total * cut_pct) / 100;
  net := total - cut;
  if p_recipient is not null and p_recipient <> p_caller and net > 0 then
    perform public.ledger_credit(p_recipient, 'earned', p_feature || '_income',
      net, p_ref, jsonb_build_object('from', p_caller, 'feature', p_feature,
      'gross', total, 'cut', cut));
    insert into public.point_events (user_id, event, amount, metadata)
      values (p_recipient, p_feature || '_income', net,
              jsonb_build_object('from', p_caller, 'ref', p_ref));
  end if;

  -- Catat revenue platform (cut).
  if cut > 0 then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values (p_feature, cut, p_caller, p_recipient, p_ref,
              jsonb_build_object('gross', total, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (p_caller, p_feature, -total,
            jsonb_build_object('units', p_units, 'ref', p_ref));

  return jsonb_build_object('ok', true, 'charged', total, 'cut', cut,
    'net', net, 'remaining', remaining, 'caller', p_caller);
end; $function$

-- snapshot-fn: chat_block_state
CREATE OR REPLACE FUNCTION public.chat_block_state(p_other uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_i_blocked boolean := false;
  v_other_blocked boolean := false;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_other is null or p_other = me then
    return jsonb_build_object(
      'i_blocked_other', false,
      'other_blocked_me', false,
      'can_send', true
    );
  end if;

  select exists (
           select 1 from public.blocks b
            where b.blocker_id = me and b.blocked_id = p_other
         ),
         exists (
           select 1 from public.blocks b
            where b.blocker_id = p_other and b.blocked_id = me
         )
    into v_i_blocked, v_other_blocked;

  return jsonb_build_object(
    'i_blocked_other', v_i_blocked,
    'other_blocked_me', v_other_blocked,
    'can_send', not (v_i_blocked or v_other_blocked)
  );
end;
$function$

-- snapshot-fn: chat_photos_guard
CREATE OR REPLACE FUNCTION public.chat_photos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage'
AS $function$
declare
  v_type  text := lower(coalesce(new.metadata->>'mimetype', ''));
  v_size  bigint := coalesce((new.metadata->>'size')::bigint, 0);
  v_video boolean;
  v_ok    boolean;
begin
  if new.bucket_id <> 'chat-photos' then
    return new;
  end if;

  -- MIME kosong: tolak (klien selalu mengirim contentType eksplisit).
  if v_type = '' then
    raise exception 'Tipe file kosong (contentType wajib dikirim).'
      using errcode = 'check_violation';
  end if;

  v_video := v_type like 'video/%' or v_type = 'application/mp4';

  -- Sumber kebenaran daftar tipe = `storage.buckets.allowed_mime_types`.
  select coalesce(v_type = any(b.allowed_mime_types), false)
    into v_ok
    from storage.buckets b
   where b.id = 'chat-photos';
  v_ok := coalesce(v_ok, false);

  if not v_ok then
    raise exception 'Tipe file tidak diizinkan: %', v_type
      using errcode = 'check_violation';
  end if;

  -- Batas ukuran: video 50 MB, file lain 20 MB (<= file_size_limit bucket).
  if v_video and v_size > 50 * 1024 * 1024 then
    raise exception 'Ukuran video melebihi batas 50 MB (%).', v_size
      using errcode = 'check_violation';
  end if;
  if not v_video and v_size > 20 * 1024 * 1024 then
    raise exception 'Ukuran file melebihi batas 20 MB (%).', v_size
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$

-- snapshot-fn: check_cron_failures
CREATE OR REPLACE FUNCTION public.check_cron_failures(p_lookback_hours integer DEFAULT 24)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inserted int := 0;
  v_rec record;
  v_detail jsonb;
  v_msg text;
  v_token text;
begin
  -- Job kritikal: kegagalan berulang = data menumpuk / fitur rusak.
  -- Sengaja eksplisit, bukan "semua job" (hindari alarm berisik).
  for v_rec in
    with critical(jobid, label) as (
      values
        (1::bigint, 'cleanup_stale_anonymous'),
        (4::bigint, 'purge_inactive_accounts'),
        (28::bigint, 'purge_location_history_90d'),
        (10::bigint, 'purge_expired_stories'),
        (22::bigint, 'ai_reply_log_prune')
    )
    select c.jobid,
           c.label,
           count(*) as fail_count,
           count(*) filter (
             where jrd.return_message not ilike '%startup timeout%'
           ) as fail_real,
           max(jrd.start_time) as last_fail,
           (array_agg(jrd.return_message order by jrd.start_time desc))[1]
             as last_error
      from critical c
      join cron.job_run_details jrd on jrd.jobid = c.jobid
     where jrd.status = 'failed'
       and jrd.start_time > now() - make_interval(hours => p_lookback_hours)
     group by c.jobid, c.label
    -- >=2 kegagalan NYATA = pola, bukan insiden sesaat.
    -- `job startup timeout` = server sibuk (transient), tidak dihitung:
    -- terbukti berisik (job 27: 87/3465 run, semuanya pulih sendiri).
    having count(*) filter (
             where jrd.return_message not ilike '%startup timeout%'
           ) >= 2
  loop
    v_detail := jsonb_build_object(
      'fail_count', v_rec.fail_count,
      'fail_real', v_rec.fail_real,
      'last_fail', v_rec.last_fail,
      'last_error', left(coalesce(v_rec.last_error, ''), 500),
      'lookback_hours', p_lookback_hours,
      -- Status run TERAKHIR — supaya admin tahu apakah masih bermasalah
      -- atau sudah pulih (mis. gagal 5× lalu diperbaiki).
      'currently_ok', (
        select coalesce(
          (array_agg(jrd.status order by jrd.start_time desc))[1] = 'succeeded',
          false
        )
          from cron.job_run_details jrd
         where jrd.jobid = v_rec.jobid
      )
    );
    v_msg := format(
      'Cron "%s" gagal %s× dalam %s jam terakhir. Error terakhir: %s',
      v_rec.label, v_rec.fail_real, p_lookback_hours,
      left(coalesce(v_rec.last_error, '-'), 160)
    );

    begin
      insert into public.admin_alerts
        (kind, severity, jobid, job_name, message, detail)
      values
        ('cron_failed', 'critical', v_rec.jobid, v_rec.label, v_msg, v_detail);
      v_inserted := v_inserted + 1;
    exception when unique_violation then
      -- Sudah ada alarm untuk job ini hari ini — jangan duplikat.
      null;
    end;

    -- Push ke device admin (bila ada token). Diam-diam gagal bila tidak ada
    -- device admin / token kosong — alarm tetap tersimpan di tabel.
    begin
      select d.fcm_token into v_token
        from public.user_devices d
        join public.profiles p on p.id = d.user_id
       where p.email = 'zunixe@gmail.com'
         and d.fcm_token is not null
         and d.fcm_token <> ''
         and coalesce(d.is_active, true)
       order by d.last_seen_at desc nulls last
       limit 1;

      if v_token is not null and v_token <> '' then
        insert into public.outbox (type, payload) values (
          'push',
          jsonb_build_object(
            'token', v_token,
            'title', '⚠️ Cron gagal',
            'body', v_msg,
            'data', jsonb_build_object(
              'type', 'admin_alert',
              'alertKind', 'cron_failed',
              'jobid', v_rec.jobid
            )
          )
        );
      end if;
    exception when others then
      null;  -- jangan gagalkan alarm hanya karena push bermasalah
    end;
  end loop;

  return v_inserted;
end;
$function$

-- snapshot-fn: check_email_exists
CREATE OR REPLACE FUNCTION public.check_email_exists(p_email text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_profile_id uuid;
    v_nickname text;
    BEGIN
      -- Cari di auth.users berdasarkan email
        SELECT au.id, pr.nickname
          INTO v_profile_id, v_nickname
            FROM auth.users au
              LEFT JOIN profiles pr ON pr.id = au.id
                WHERE au.email = p_email
                  AND au.id != auth.uid()
                    LIMIT 1;
                      
                        IF v_profile_id IS NULL THEN
                            RETURN json_build_object('exists', false);
                              END IF;
                                
                                  RETURN json_build_object(
                                      'exists', true,
                                          'profile_id', v_profile_id,
                                              'nickname', v_nickname
                                                );
                                                END;
                                                $function$

-- snapshot-fn: check_email_registered
CREATE OR REPLACE FUNCTION public.check_email_registered(p_email text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
      select 1 from auth.users where lower(email) = lower(p_email)
        );
        $function$

-- snapshot-fn: check_private_chat_update
CREATE OR REPLACE FUNCTION public.check_private_chat_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Admin (email claim / DB email / service_role) boleh update apapun
  -- (dipakai sync_profile_to_chats dari admin_update_dummy_profile).
  if public.is_admin_request() then
    return new;
  end if;
  -- Hanya participant yang boleh update
  if not (auth.uid() = any (new.participants)) then
    raise exception 'Not authorized';
  end if;
  -- Participant tidak boleh diubah setelah dibuat
  if new.participants != old.participants then
    raise exception 'Cannot modify participants';
  end if;
  return new;
end;
$function$

-- snapshot-fn: claim_nickname
CREATE OR REPLACE FUNCTION public.claim_nickname(p_nickname text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_registered boolean;
  v_last_seen timestamptz;
  v_new_nick text;
begin
  if public.is_banned_nickname(p_nickname)
     and not public.is_admin_request() then
    return false;
  end if;

  select id, coalesce(is_registered, false), coalesce(last_seen, created_at)
    into v_owner, v_registered, v_last_seen
    from profiles
   where lower(trim(nickname)) = lower(trim(p_nickname))
   limit 1;

  if v_owner is null or v_owner = auth.uid() or v_registered then
    return false;
  end if;

  if v_last_seen > now() - interval '7 days' then
    return false;
  end if;

  -- Nickname baru pengambil (kalau dia sedang mengubah nickname ke ini).
  select nickname into v_new_nick from profiles where id = auth.uid();

  perform public.fn_archive_deleted_user(v_owner, 'nickname_claim', auth.uid(), v_new_nick);

  delete from comment_likes where user_id = v_owner;
  delete from comment_shares where user_id = v_owner;
  delete from contact_messages where user_id = v_owner;
  delete from follows where follower_id = v_owner or followee_id = v_owner;
  delete from friend_requests where from_id = v_owner or to_id = v_owner;
  delete from kyc_requests where user_id = v_owner;
  delete from post_comments where author_id = v_owner;
  delete from post_likes where user_id = v_owner;
  delete from post_shares where user_id = v_owner;
  delete from posts where author_id = v_owner;
  delete from referral_rewards where referred_id = v_owner or referrer_id = v_owner;
  delete from subscriptions where subscriber_id = v_owner or creator_id = v_owner;
  delete from user_photos where user_id = v_owner;
  delete from withdrawal_requests where user_id = v_owner;

  delete from profiles where id = v_owner;
  return true;
end;
$function$

-- snapshot-fn: claim_referral_reward
CREATE OR REPLACE FUNCTION public.claim_referral_reward()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return jsonb_build_object('rewarded', false, 'reason', 'disabled');
end; $function$

-- snapshot-fn: claim_weekly_quest
CREATE OR REPLACE FUNCTION public.claim_weekly_quest(quest_key text, tz_offset_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return jsonb_build_object('points', public.yukcoin_total(auth.uid()), 'claimed', false);
end; $function$

-- snapshot-fn: clamp_last_seen
CREATE OR REPLACE FUNCTION public.clamp_last_seen()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.last_seen is not null and new.last_seen > now() then
    new.last_seen := now();
    -- last_seen di masa depan = jam HP maju → status tak dapat dipercaya.
    -- Set offline; heartbeat berikutnya dari app akan mengembalikan online
    -- (goOnline set status='online' lagi) bila user benar-benar aktif.
    new.status := 'offline';
  end if;
  return new;
end;
$function$

-- snapshot-fn: cleanup_expired_rooms
CREATE OR REPLACE FUNCTION public.cleanup_expired_rooms()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.rooms
   where is_private = true and expires_at is not null and expires_at <= now();
end;
$function$

-- snapshot-fn: cleanup_room_presence
CREATE OR REPLACE FUNCTION public.cleanup_room_presence(p_minutes integer DEFAULT 10)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare deleted int;
begin
  p_minutes := least(greatest(coalesce(p_minutes,10),1), 60);
  delete from public.room_presence where joined_at < now() - (p_minutes || ' minutes')::interval;
  get diagnostics deleted = row_count;
  return deleted;
end; $function$

-- snapshot-fn: cleanup_stale_anonymous
CREATE OR REPLACE FUNCTION public.cleanup_stale_anonymous(min_age_days integer DEFAULT 7)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  deleted int := 0;
  r record;
begin
  -- Hanya user anon yang TERBUKTI idle >= min_age_days.
  -- Semua jalur data (last_seen / profil.created_at / auth.created_at)
  -- dipakai; bila tak satu pun tersedia, user TIDAK dihapus (fail-safe).
  for r in
    select u.id
    from auth.users u
    left join public.profiles p on p.id = u.id
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.dummy_accounts d where d.uid = u.id
      )
      and coalesce(
            p.last_seen,
            p.created_at,
            u.created_at
          ) is not null
      and coalesce(
            p.last_seen,
            p.created_at,
            u.created_at
          ) < now() - make_interval(days => min_age_days)
  loop
    begin
      perform public.fn_archive_deleted_user(r.id, 'stale_cleanup');
      delete from public.room_presence where user_id = r.id;
      delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
      delete from public.reports where reporter_id = r.id or reported_id = r.id;
      delete from public.user_photos where user_id = r.id;

      delete from public.private_messages pm
      using public.private_chats pc
      where pm.chat_id = pc.chat_id
        and pc.participants @> array[r.id]::uuid[];

      delete from public.private_chats pc
      where pc.participants @> array[r.id]::uuid[];

      delete from public.private_messages where sender_id = r.id;

      -- Device & location WAJIB dihapus SEBELUM profiles (FK SET NULL tapi
      -- kolom NOT NULL → 23503 bila profiles dihapus lebih dulu).
      delete from public.user_devices where user_id = r.id;
      delete from public.user_location_history where user_id = r.id;
      delete from public.contact_messages where user_id = r.id;

      delete from public.profiles where id = r.id;

      -- Ledger koin & point_events: trigger append-only menolak DELETE, dan
      -- cascade dari auth.users pun ditolak → matikan trigger sementara.
      alter table public.coin_ledger disable trigger coin_ledger_no_delete;
      delete from public.coin_ledger where user_id = r.id;
      alter table public.coin_ledger enable trigger coin_ledger_no_delete;

      delete from public.point_events where user_id = r.id;

      delete from auth.users where id = r.id;
      deleted := deleted + 1;
    exception when others then
      -- Satu user gagal (mis. data aneh) tidak boleh menggagalkan seluruh
      -- cleanup — lanjut ke user berikutnya.
      null;
    end;
  end loop;
  return deleted;
end;
$function$

-- snapshot-fn: cleanup_stale_presence
CREATE OR REPLACE FUNCTION public.cleanup_stale_presence(min_age_minutes integer DEFAULT 10)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  deleted int := 0;
begin
  delete from public.room_presence
  where joined_at < now() - make_interval(mins => min_age_minutes);
  get diagnostics deleted = row_count;
  return deleted;
end;
$function$

-- snapshot-fn: clear_anon_social
CREATE OR REPLACE FUNCTION public.clear_anon_social()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.follows
  where follower_id = auth.uid();
  delete from public.subscriptions
  where subscriber_id = auth.uid();
  delete from public.friend_requests
  where from_id = auth.uid();
end;
$function$

-- snapshot-fn: coin_ledger_no_mutate
CREATE OR REPLACE FUNCTION public.coin_ledger_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception 'coin_ledger is append-only';
end; $function$

-- snapshot-fn: comment_like_count_sync
CREATE OR REPLACE FUNCTION public.comment_like_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    update public.post_comments set like_count = like_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.post_comments set like_count = greatest(like_count - 1, 0) where id = old.comment_id;
  end if;
  return null;
end; $function$

-- snapshot-fn: comment_share_count_sync
CREATE OR REPLACE FUNCTION public.comment_share_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    update public.post_comments set share_count = share_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.post_comments set share_count = greatest(share_count - 1, 0) where id = old.comment_id;
  end if;
  return null;
end; $function$

-- snapshot-fn: count_room_presence_by_country
CREATE OR REPLACE FUNCTION public.count_room_presence_by_country(p_country text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rows jsonb;
begin
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;
  select coalesce(jsonb_object_agg(r.room_id, r.cnt), '{}'::jsonb) into rows
  from (
    select rp.room_id, count(*)::int as cnt
    from public.room_presence rp
    join public.profiles pr on pr.id = rp.user_id
    where rp.joined_at > now() - interval '10 minutes'
      and (p_country is null or pr.country = p_country)
    group by rp.room_id
  ) r;
  return coalesce(rows, '{}'::jsonb);
end; $function$

-- snapshot-fn: create_post (overload 1)
CREATE OR REPLACE FUNCTION public.create_post(p_text text DEFAULT ''::text, p_image_path text DEFAULT ''::text, p_visibility text DEFAULT 'public'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  am_registered boolean; my_name text; my_gender text;
  daily_lim int; today_count int; new_id uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_visibility not in ('public','followers','subscribers') then
    raise exception 'Invalid visibility';
  end if;
  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;
  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) > 2000 then raise exception 'Post too long'; end if;
  if p_text = '' and coalesce(p_image_path, '') = '' then
    raise exception 'Empty post';
  end if;
  select posts_daily_limit into daily_lim from public.app_settings where id = 'global';
  select count(*) into today_count from public.posts
    where author_id = me and created_at >= date_trunc('day', now());
  if today_count >= coalesce(daily_lim, 5) then
    raise exception 'Daily post limit reached';
  end if;
  insert into public.posts (author_id, author_name, author_gender, text, image_path, images, visibility)
    values (me, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_text, coalesce(p_image_path,''),
            case when coalesce(p_image_path,'')='' then '{}' else array[p_image_path] end,
            p_visibility)
    returning id into new_id;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $function$

-- snapshot-fn: create_post (overload 2)
CREATE OR REPLACE FUNCTION public.create_post(p_text text DEFAULT ''::text, p_image_paths text[] DEFAULT '{}'::text[], p_visibility text DEFAULT 'public'::text, p_image_dims jsonb DEFAULT '[]'::jsonb, p_image_blurhashes jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  am_registered boolean; my_name text; my_gender text;
  daily_lim int; today_count int; new_id uuid;
  v_w int := 0; v_h int := 0; v_dims jsonb; v_bh jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_visibility not in ('public','followers','subscribers') then
    raise exception 'Invalid visibility';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;

  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) > 2000 then raise exception 'Post too long'; end if;
  if coalesce(array_length(p_image_paths, 1), 0) > 5 then
    raise exception 'Too many photos';
  end if;
  if p_text = '' and coalesce(array_length(p_image_paths, 1), 0) = 0 then
    raise exception 'Empty post';
  end if;

  -- Normalisasi dimensi: pakai elemen pertama yang valid untuk image_w/h.
  v_dims := case when jsonb_typeof(p_image_dims) = 'array'
                 then p_image_dims else '[]'::jsonb end;
  if jsonb_array_length(v_dims) > 0 then
    v_w := coalesce((v_dims->0->>'w')::int, 0);
    v_h := coalesce((v_dims->0->>'h')::int, 0);
    if v_w < 0 then v_w := 0; end if;
    if v_h < 0 then v_h := 0; end if;
  end if;

  -- Normalisasi blurhash (array string; elemen kosong dibuang).
  v_bh := case when jsonb_typeof(p_image_blurhashes) = 'array'
               then p_image_blurhashes else '[]'::jsonb end;

  select posts_daily_limit into daily_lim from public.app_settings where id = 'global';
  select count(*) into today_count from public.posts
    where author_id = me and created_at >= date_trunc('day', now());
  if today_count >= coalesce(daily_lim, 5) then
    raise exception 'Daily post limit reached';
  end if;

  insert into public.posts (
    author_id, author_name, author_gender, text, image_path, images,
    image_w, image_h, image_dims, image_blurhashes, visibility)
    values (me, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_text, coalesce(p_image_paths[1], ''),
            coalesce(p_image_paths, '{}'::text[]),
            v_w, v_h, v_dims, v_bh, p_visibility)
    returning id into new_id;

  return jsonb_build_object(
    'ok', true,
    'id', new_id,
    'daily_remaining', greatest(0, coalesce(daily_lim, 5) - today_count - 1)
  );
end; $function$

-- snapshot-fn: create_private_room
CREATE OR REPLACE FUNCTION public.create_private_room(p_name text, p_icon text, p_country text, p_password text DEFAULT NULL::text, p_category text DEFAULT 'private'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  uid uuid := auth.uid(); points_on boolean;
  has_pw boolean := (p_password is not null and length(p_password) > 0);
  active_count int; new_id text; my_name text;
  paid int; create_paid int; create_pw_paid int; bonus_p int; mult int;
  remaining int; r jsonb;
  is_admin boolean := ((auth.jwt() ->> 'email') = 'zunixe@gmail.com');
  v_token text;
  recent_id text;
  v_cat text;
  v_is_category boolean;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  -- Grup hanya untuk TERDAFTAR (bypass: dummy & admin).
  if not is_admin
     and uid not in (select du from public.admin_dummy_uids() du)
     and not coalesce(
       (select is_registered from public.profiles where id = uid), false)
  then
    raise exception 'REGISTERED_ONLY';
  end if;
  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then raise exception 'Invalid room name'; end if;
  if p_country is null or p_country = '' then raise exception 'Invalid country'; end if;

  -- Kategori: allowlist 11 kategori global + 'private' (legacy grup).
  v_cat := coalesce(nullif(btrim(coalesce(p_category, '')), ''), 'private');
  if v_cat not in ('general', 'curhat', 'pertemanan', 'teknologi', 'gaming',
                   'musik', 'film', 'joke', 'belajar', 'flirt', 'jualbeli',
                   'private') then
    raise exception 'Invalid category';
  end if;
  v_is_category := (v_cat <> 'private');

  -- Room kategori = GLOBAL: tanpa password (abaikan p_password bila ada).
  if v_is_category then
    has_pw := false;
    p_password := null;
  end if;

  -- Idempotency: jika ada room nama sama owner sama dibuat <10 detik lalu, kembalikan itu
  select id into recent_id from public.rooms
   where owner_id = uid and is_private = true and name = p_name
     and created_at > now() - interval '10 seconds'
   order by created_at desc limit 1;
  if recent_id is not null then
    select join_token into v_token from public.rooms where id = recent_id;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('id', recent_id, 'points', coalesce(remaining, 0), 'join_token', v_token, 'duplicate', true);
  end if;

  if not is_admin then
    select count(*) into active_count from public.rooms
     where owner_id = uid and is_private = true
       and (expires_at is null or expires_at > now());
    if active_count >= 2 then raise exception 'Room limit reached'; end if;
  end if;

  select points_enabled, room_create_paid, room_create_pw_paid, bonus_price_multiplier
    into points_on, create_paid, create_pw_paid, mult from app_settings where id = 'global';
  paid := case when has_pw then create_pw_paid else create_paid end;
  bonus_p := paid * mult;

  -- Room kategori = GRATIS (tidak potong koin). Legacy 'private' tetap bayar.
  if points_on is not false and not is_admin and not v_is_category then
    r := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'create');
    remaining := (r->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  select nickname into my_name from public.profiles where id = uid;
  new_id := 'pr_' || replace(gen_random_uuid()::text, '-', '');
  v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 22);

  insert into public.rooms (id, name, description, icon, "order", country, category,
                            is_private, owner_id, owner_name, password_hash, has_password,
                            expires_at, created_at,
                            join_token, max_members, approval_required)
  values (new_id, p_name, '', coalesce(nullif(p_icon, ''), '🔒'), 999, p_country, v_cat,
          -- PEMISAH: kategori = GLOBAL (false). Legacy grup = private (true).
          case when v_is_category then false else true end,
          uid, coalesce(my_name, 'Anon'),
          case when has_pw then crypt(p_password, gen_salt('bf')) else null end,
          has_pw,
          -- TANPA password = permanen (NULL); DENGAN password = 7 hari.
          case when has_pw then now() + interval '7 days' else null end,
          now(),
          -- Kategori = terbuka (tanpa approval, maks 200). Legacy = antre + maks 20.
          v_token, case when v_is_category then 200 else 20 end,
          case when v_is_category then false else true end);

  insert into public.room_members (room_id, user_id, role)
  values (new_id, uid, 'owner') on conflict do nothing;

  return jsonb_build_object('id', new_id, 'points', coalesce(remaining, 0), 'join_token', v_token);
end;
$function$

-- snapshot-fn: create_story
CREATE OR REPLACE FUNCTION public.create_story(p_image_path text, p_text_overlay text DEFAULT ''::text, p_text_x real DEFAULT 0.5, p_text_y real DEFAULT 0.85, p_text_color integer DEFAULT 0, p_text_size integer DEFAULT 1, p_text_bg boolean DEFAULT false, p_text_scale real DEFAULT 1.0, p_text_rotation real DEFAULT 0, p_visibility text DEFAULT 'followers'::text, p_media_type text DEFAULT 'image'::text, p_video_path text DEFAULT ''::text, p_duration_ms integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_vis text;
  v_media text;
begin
  if not public._viewer_is_registered() then
    v_vis := 'everyone';
  elsif p_visibility not in ('everyone','followers','friends') then
    if p_visibility = 'registered' then
      v_vis := 'followers';
    else
      raise exception 'Visibility tidak valid';
    end if;
  else
    v_vis := p_visibility;
  end if;
  if length(coalesce(p_text_overlay, '')) > 300 then
    raise exception 'Teks terlalu panjang (max 300)';
  end if;
  v_media := coalesce(p_media_type, 'image');
  if v_media not in ('image', 'video') then
    raise exception 'Media tidak valid';
  end if;
  if v_media = 'video' then
    if coalesce(p_video_path, '') = ''
       or p_video_path not like 'story/%' then
      raise exception 'Video path tidak valid';
    end if;
    if coalesce(p_duration_ms, 0) < 1000
       or coalesce(p_duration_ms, 0) > 15000 then
      raise exception 'Durasi video 1-15 detik';
    end if;
  end if;
  insert into public.stories (
    author_id, author_name, image_path, text_overlay, text_x, text_y,
    text_color, text_size, text_bg, text_scale, text_rotation, visibility,
    media_type, video_path, duration_ms
  )
  select auth.uid(),
         coalesce((select nickname from public.profiles where id = auth.uid()), 'Anon'),
         p_image_path, coalesce(p_text_overlay, ''),
         greatest(least(coalesce(p_text_x, 0.5), 1), 0),
         greatest(least(coalesce(p_text_y, 0.85), 1), 0),
         greatest(least(coalesce(p_text_color, 0), 7), 0),
         greatest(least(coalesce(p_text_size, 1), 2), 0),
         coalesce(p_text_bg, false),
         greatest(coalesce(p_text_scale, 1.0), 0.1),
         coalesce(p_text_rotation, 0),
         v_vis,
         v_media, coalesce(p_video_path, ''),
         greatest(coalesce(p_duration_ms, 0), 0)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$

-- snapshot-fn: create_topup_order
CREATE OR REPLACE FUNCTION public.create_topup_order(p_order_id text, p_user uuid, p_package_id text, p_snap_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pk record;
begin
  select * into pk from topup_packages where id = p_package_id and active = true;
  if not found then raise exception 'Invalid package'; end if;

  insert into topup_orders (id, user_id, package_id, coins, price_idr, status, snap_token)
    values (p_order_id, p_user, pk.id, pk.coins, pk.price_idr, 'pending', p_snap_token);

  return jsonb_build_object('order_id', p_order_id, 'coins', pk.coins,
    'price_idr', pk.price_idr);
end; $function$

-- snapshot-fn: credit_play_topup
CREATE OR REPLACE FUNCTION public.credit_play_topup(p_user uuid, p_play_product_id text, p_purchase_token text, p_play_order_id text DEFAULT NULL::text, p_raw jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  pk record; me_order text; tot int; existing record;
begin
  if p_user is null then raise exception 'Missing user'; end if;
  if p_purchase_token is null or length(p_purchase_token) < 4 then
    raise exception 'Invalid purchase token';
  end if;

  -- Idempotensi: token sudah pernah di-credit?
  select * into existing from topup_orders where purchase_token = p_purchase_token;
  if found then
    return jsonb_build_object('ok', true, 'already', true,
      'coins', existing.coins, 'total', public.yukcoin_total(p_user));
  end if;

  -- Cari paket berdasarkan produk Play.
  select * into pk from topup_packages
    where play_product_id = p_play_product_id and active = true;
  if not found then raise exception 'Unknown Play product: %', p_play_product_id; end if;

  me_order := 'play_' || replace(gen_random_uuid()::text, '-', '');

  insert into topup_orders (id, user_id, package_id, coins, price_idr, status,
                            provider, provider_ref, purchase_token, play_order_id,
                            platform, raw, paid_at)
    values (me_order, p_user, pk.id, pk.coins, pk.price_idr, 'paid',
            'play_billing', p_play_order_id, p_purchase_token, p_play_order_id,
            'play', coalesce(p_raw, '{}'::jsonb), now());

  -- Coin masuk bucket 'topup' (lineage uang asli).
  tot := public.ledger_credit(p_user, 'topup', 'topup', pk.coins,
           me_order, jsonb_build_object('play_product', p_play_product_id,
           'price_idr', pk.price_idr));

  return jsonb_build_object('ok', true, 'already', false, 'coins', pk.coins,
    'total', tot, 'order_id', me_order);
end; $function$

-- snapshot-fn: credit_topup_order
CREATE OR REPLACE FUNCTION public.credit_topup_order(p_order_id text, p_status text, p_provider_ref text DEFAULT NULL::text, p_raw jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o record; tot int;
begin
  select * into o from topup_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found: %', p_order_id; end if;

  -- Sudah paid → idempoten, jangan double-credit
  if o.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'coins', o.coins);
  end if;

  if p_status = 'paid' then
    update topup_orders set status = 'paid', provider_ref = p_provider_ref,
      raw = coalesce(p_raw,'{}'::jsonb), paid_at = now()
      where id = p_order_id;

    tot := public.ledger_credit(o.user_id, 'topup', 'topup', o.coins,
      p_order_id, jsonb_build_object('order_id', p_order_id, 'price_idr', o.price_idr));

    return jsonb_build_object('ok', true, 'credited', o.coins, 'total', tot);
  else
    update topup_orders set status = p_status, provider_ref = p_provider_ref,
      raw = coalesce(p_raw,'{}'::jsonb)
      where id = p_order_id;
    return jsonb_build_object('ok', true, 'status', p_status);
  end if;
end; $function$

-- snapshot-fn: credit_welcome_bonus
CREATE OR REPLACE FUNCTION public.credit_welcome_bonus(p_user uuid, p_install_id text, p_kind text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  coins int; max_ip int; ip_count int; tot int; existing int;
begin
  if p_user is null then raise exception 'Missing user'; end if;
  if p_kind not in ('anon','register') then
    raise exception 'Invalid kind: %', p_kind;
  end if;
  if p_install_id is null or length(trim(p_install_id)) < 6 then
    raise exception 'Invalid install_id';
  end if;

  select case p_kind
           when 'anon' then coalesce(welcome_anon_coins,100)
           else coalesce(welcome_register_coins,100) end,
         coalesce(welcome_max_claims_per_ip_day, 3)
    into coins, max_ip
    from app_settings where id = 'global';

  -- Lapis 1: install_id + kind sudah pernah klaim?
  select count(*) into existing from public.bonus_claims
    where install_id = p_install_id and kind = p_kind;
  if existing > 0 then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'already_claimed', 'coins', 0,
      'total', public.yukcoin_total(p_user));
  end if;

  -- Lapis 2: limit klaim per IP / 24 jam (bila IP tersedia).
  if p_ip is not null and length(trim(p_ip)) > 0 then
    select count(*) into ip_count from public.bonus_claims
      where ip = p_ip and kind = p_kind
        and created_at > now() - interval '24 hours';
    if ip_count >= max_ip then
      return jsonb_build_object('ok', true, 'granted', false,
        'reason', 'ip_limit', 'coins', 0,
        'total', public.yukcoin_total(p_user));
    end if;
  end if;

  -- Beri bonus (semua ke bucket 'bonus').
  insert into public.bonus_claims(install_id, kind, user_id, ip)
    values (p_install_id, p_kind, p_user, nullif(trim(coalesce(p_ip,'')), ''))
    on conflict (install_id, kind) do nothing;
  if not found then
    return jsonb_build_object('ok', true, 'granted', false,
      'reason', 'race', 'coins', 0, 'total', public.yukcoin_total(p_user));
  end if;

  tot := public.ledger_credit(p_user, 'bonus', 'welcome_' || p_kind, coins,
           null, jsonb_build_object('install_id', p_install_id, 'ip', p_ip));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, 'welcome_' || p_kind, coins,
            jsonb_build_object('install_id', p_install_id));

  return jsonb_build_object('ok', true, 'granted', true, 'coins', coins,
    'total', tot);
end; $function$

-- snapshot-fn: cube (overload 1)
CREATE OR REPLACE FUNCTION public.cube(double precision[], double precision[])
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_a_f8_f8$function$

-- snapshot-fn: cube (overload 2)
CREATE OR REPLACE FUNCTION public.cube(double precision[])
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_a_f8$function$

-- snapshot-fn: cube (overload 3)
CREATE OR REPLACE FUNCTION public.cube(double precision)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_f8$function$

-- snapshot-fn: cube (overload 4)
CREATE OR REPLACE FUNCTION public.cube(double precision, double precision)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_f8_f8$function$

-- snapshot-fn: cube (overload 5)
CREATE OR REPLACE FUNCTION public.cube(cube, double precision)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_c_f8$function$

-- snapshot-fn: cube (overload 6)
CREATE OR REPLACE FUNCTION public.cube(cube, double precision, double precision)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_c_f8_f8$function$

-- snapshot-fn: cube_cmp
CREATE OR REPLACE FUNCTION public.cube_cmp(cube, cube)
 RETURNS integer
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_cmp$function$

-- snapshot-fn: cube_contained
CREATE OR REPLACE FUNCTION public.cube_contained(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_contained$function$

-- snapshot-fn: cube_contains
CREATE OR REPLACE FUNCTION public.cube_contains(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_contains$function$

-- snapshot-fn: cube_coord
CREATE OR REPLACE FUNCTION public.cube_coord(cube, integer)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_coord$function$

-- snapshot-fn: cube_coord_llur
CREATE OR REPLACE FUNCTION public.cube_coord_llur(cube, integer)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_coord_llur$function$

-- snapshot-fn: cube_dim
CREATE OR REPLACE FUNCTION public.cube_dim(cube)
 RETURNS integer
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_dim$function$

-- snapshot-fn: cube_distance
CREATE OR REPLACE FUNCTION public.cube_distance(cube, cube)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_distance$function$

-- snapshot-fn: cube_enlarge
CREATE OR REPLACE FUNCTION public.cube_enlarge(cube, double precision, integer)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_enlarge$function$

-- snapshot-fn: cube_eq
CREATE OR REPLACE FUNCTION public.cube_eq(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_eq$function$

-- snapshot-fn: cube_ge
CREATE OR REPLACE FUNCTION public.cube_ge(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_ge$function$

-- snapshot-fn: cube_gt
CREATE OR REPLACE FUNCTION public.cube_gt(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_gt$function$

-- snapshot-fn: cube_in
CREATE OR REPLACE FUNCTION public.cube_in(cstring)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_in$function$

-- snapshot-fn: cube_inter
CREATE OR REPLACE FUNCTION public.cube_inter(cube, cube)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_inter$function$

-- snapshot-fn: cube_is_point
CREATE OR REPLACE FUNCTION public.cube_is_point(cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_is_point$function$

-- snapshot-fn: cube_le
CREATE OR REPLACE FUNCTION public.cube_le(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_le$function$

-- snapshot-fn: cube_ll_coord
CREATE OR REPLACE FUNCTION public.cube_ll_coord(cube, integer)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_ll_coord$function$

-- snapshot-fn: cube_lt
CREATE OR REPLACE FUNCTION public.cube_lt(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_lt$function$

-- snapshot-fn: cube_ne
CREATE OR REPLACE FUNCTION public.cube_ne(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_ne$function$

-- snapshot-fn: cube_out
CREATE OR REPLACE FUNCTION public.cube_out(cube)
 RETURNS cstring
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_out$function$

-- snapshot-fn: cube_overlap
CREATE OR REPLACE FUNCTION public.cube_overlap(cube, cube)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_overlap$function$

-- snapshot-fn: cube_recv
CREATE OR REPLACE FUNCTION public.cube_recv(internal)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_recv$function$

-- snapshot-fn: cube_send
CREATE OR REPLACE FUNCTION public.cube_send(cube)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_send$function$

-- snapshot-fn: cube_size
CREATE OR REPLACE FUNCTION public.cube_size(cube)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_size$function$

-- snapshot-fn: cube_subset
CREATE OR REPLACE FUNCTION public.cube_subset(cube, integer[])
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_subset$function$

-- snapshot-fn: cube_union
CREATE OR REPLACE FUNCTION public.cube_union(cube, cube)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_union$function$

-- snapshot-fn: cube_ur_coord
CREATE OR REPLACE FUNCTION public.cube_ur_coord(cube, integer)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$cube_ur_coord$function$

-- snapshot-fn: daily_login_bonus
CREATE OR REPLACE FUNCTION public.daily_login_bonus()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cur_points int;
begin
  select points into cur_points from profiles where id = auth.uid();
  return jsonb_build_object('points', coalesce(cur_points, 0), 'streak', 0, 'bonus', 0);
end; $function$

-- snapshot-fn: deduct_chat_point
CREATE OR REPLACE FUNCTION public.deduct_chat_point(msg_type text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare points_on boolean; cost int; remaining int; c_text int; c_img int; c_vo int;
begin
  select points_enabled, cost_chat_text, cost_chat_image, cost_view_once
    into points_on, c_text, c_img, c_vo from app_settings where id = 'global';
  if points_on is false then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;

  cost := case msg_type
    when 'image' then c_img
    when 'view_once' then c_vo
    when 'view_once_expired' then 0
    else c_text end;

  if cost = 0 then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;

  remaining := public.ledger_spend(auth.uid(), 'spend_chat', cost, msg_type);
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));
  return remaining;
end; $function$

-- snapshot-fn: delete_my_account
CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_deleted_chats int := 0;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com' then
    raise exception 'ADMIN_DELETE_FORBIDDEN';
  end if;

  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  perform public.fn_archive_deleted_user(v_uid, 'self_delete');

  -- Relasi sosial
  delete from public.follows where follower_id = v_uid or followee_id = v_uid;
  delete from public.friend_requests where from_id = v_uid or to_id = v_uid;
  delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
  delete from public.subscriptions where subscriber_id = v_uid or creator_id = v_uid;

  -- Chat 1:1: baris DIPERTAHANKAN + ditandai; ISI PESAN dihapus.
  -- Lawan melihat label "Akun dihapus" dan bisa menghapusnya sendiri.
  v_deleted_chats := public.mark_chats_user_deleted(v_uid);

  -- Pesan & konten
  delete from public.private_messages where sender_id = v_uid;
  -- Pesan room: SOFT-delete (is_deleted) supaya tampil "Pesan dihapus"
  -- di room — JANGAN hard-delete (pesan hilang total). Klien me-render
  -- placeholder dari flag ini (RoomMessageBubble). Isi teks tetap di DB
  -- (konsisten dgn pesan yang dihapus sendiri); arsip sudah dibuat di atas.
  update public.messages set is_deleted = true where sender_id = v_uid;
  delete from public.room_members where user_id = v_uid;
  delete from public.room_join_requests where user_id = v_uid;
  delete from public.room_presence where user_id = v_uid;
  delete from public.stories where author_id = v_uid;
  delete from public.story_views where viewer_id = v_uid;
  delete from public.user_photos where user_id = v_uid;
  delete from public.photo_unlocks where viewer_id = v_uid;
  delete from public.posts where author_id = v_uid;
  delete from public.post_comments where author_id = v_uid;
  delete from public.comment_likes where user_id = v_uid;
  delete from public.post_likes where user_id = v_uid;
  delete from public.comment_shares where user_id = v_uid;
  delete from public.post_shares where user_id = v_uid;

  -- Ledger koin: trigger append-only menolak DELETE → matikan sementara.
  set local session_replication_role = 'replica';
  delete from public.coin_ledger where user_id = v_uid;
  delete from public.point_events where user_id = v_uid;
  set local session_replication_role = 'origin';
  delete from public.calls where caller_id = v_uid or callee_id = v_uid;
  delete from public.call_signals where from_uid = v_uid;

  -- Device & location history: FK-nya SET NULL tapi kolom user_id NOT NULL
  -- → hapus eksplisit SEBELUM profiles (lihat header file).
  delete from public.user_devices where user_id = v_uid;
  delete from public.user_location_history where user_id = v_uid;

  delete from public.profiles where id = v_uid;
  delete from auth.users where id = v_uid;

  return jsonb_build_object('ok', true, 'deleted_chats', v_deleted_chats);
end;
$function$

-- snapshot-fn: delete_private_room
CREATE OR REPLACE FUNCTION public.delete_private_room(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  admin_email text := coalesce(auth.email(), '');
  r record;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then return; end if;
  -- Owner ATAU admin boleh menghapus.
  if r.owner_id <> uid and admin_email <> 'zunixe@gmail.com' then
    raise exception 'Not owner';
  end if;
  -- messages, room_members, room_presence ikut terhapus via FK cascade
  delete from public.rooms where id = p_room_id;
end;
$function$

-- snapshot-fn: delete_story
CREATE OR REPLACE FUNCTION public.delete_story(p_story_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_path text;
begin
  select image_path into v_path from public.stories
  where id = p_story_id
    and (author_id = auth.uid() or public.is_admin_request());
  if v_path is null then
    raise exception 'Unauthorized';
  end if;
  -- Semua "hapus" (user sendiri MAUPUN admin) = jadikan PRIVATE (owner_only).
  -- Pembuat & admin tetap lihat; orang lain tidak. Tidak ada yang hilang.
  update public.stories set owner_only = true where id = p_story_id;
  return jsonb_build_object('ok', true, 'image_path', v_path);
end;
$function$

-- snapshot-fn: distance_chebyshev
CREATE OR REPLACE FUNCTION public.distance_chebyshev(cube, cube)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$distance_chebyshev$function$

-- snapshot-fn: distance_taxicab
CREATE OR REPLACE FUNCTION public.distance_taxicab(cube, cube)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$distance_taxicab$function$

-- snapshot-fn: dummy_heartbeat
CREATE OR REPLACE FUNCTION public.dummy_heartbeat()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  update public.profiles p
     set last_seen = now()
   where p.id in (select uid from public.dummy_accounts)
     and p.status in ('online', 'idle');
  get diagnostics n = row_count;
  return jsonb_build_object('refreshed', n);
end;
$function$

-- snapshot-fn: dummy_uids
CREATE OR REPLACE FUNCTION public.dummy_uids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select uid from public.dummy_accounts where uid is not null;
$function$

-- snapshot-fn: earth
CREATE OR REPLACE FUNCTION public.earth()
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
RETURN '6378168'::double precision

-- snapshot-fn: earth_box
CREATE OR REPLACE FUNCTION public.earth_box(earth, double precision)
 RETURNS cube
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN cube_enlarge(($1)::cube, gc_to_sec($2), 3)

-- snapshot-fn: earth_distance
CREATE OR REPLACE FUNCTION public.earth_distance(earth, earth)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN sec_to_gc(cube_distance(($1)::cube, ($2)::cube))

-- snapshot-fn: edit_message_v2
CREATE OR REPLACE FUNCTION public.edit_message_v2(p_message_id bigint, p_new_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); cost int; owner uuid; r jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;
  if p_new_text is null or length(btrim(p_new_text)) = 0 then
    raise exception 'Teks kosong';
  end if;
  if length(p_new_text) > 2000 then raise exception 'Teks terlalu panjang'; end if;

  select cost_edit_message into cost from app_settings where id = 'global';
  select sender_id into owner from public.private_messages where id = p_message_id;
  if owner is null then raise exception 'Message not found'; end if;
  if owner <> me then raise exception 'Bukan pesanmu'; end if;

  r := public.spend_yukcoin(me, 'edit_message', cost, p_message_id::text);

  update public.private_messages
     set text = p_new_text
   where id = p_message_id and sender_id = me;

  return jsonb_build_object('ok', true, 'cost', cost,
    'remaining', (r->>'remaining')::int);
end; $function$

-- snapshot-fn: email_finalize_campaign
CREATE OR REPLACE FUNCTION public.email_finalize_campaign(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare remaining int;
begin
  select count(*) into remaining from email_recipients
   where campaign_id = p_id and status in ('pending','sending');
  if remaining = 0 then
    update email_campaigns set status = 'sent',
      sent_at = coalesce(sent_at, now()), updated_at = now()
    where id = p_id and status in ('queued','sending');
    return jsonb_build_object('done', true);
  end if;
  return jsonb_build_object('done', false, 'remaining', remaining);
end; $function$

-- snapshot-fn: email_mark_failed
CREATE OR REPLACE FUNCTION public.email_mark_failed(p_recipient_id bigint, p_error text, p_permanent boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rc int; max_r int; done boolean;
begin
  select retry_count into rc from email_recipients where id = p_recipient_id;
  select email_max_retry into max_r from app_settings where id = 'global';
  max_r := coalesce(max_r, 3);
  done := p_permanent or coalesce(rc,0) >= max_r;
  update email_recipients set
    status = case when done then 'failed' else 'pending' end,
    error = left(coalesce(p_error,''), 500)
  where id = p_recipient_id;
  return jsonb_build_object('status', case when done then 'failed' else 'pending' end);
end; $function$

-- snapshot-fn: email_mark_sent
CREATE OR REPLACE FUNCTION public.email_mark_sent(p_recipient_id bigint, p_msg_id text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update email_recipients set
    status = 'sent', sent_at = now(), provider_message_id = nullif(p_msg_id,''), error = null
  where id = p_recipient_id;
$function$

-- snapshot-fn: email_recount_campaign
CREATE OR REPLACE FUNCTION public.email_recount_campaign(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s int; d int; o int; cl int; bo int; un int; tot int;
begin
  select
    count(*) filter (where status in ('sent','delivered','opened','clicked')),
    count(*) filter (where status = 'delivered'),
    count(*) filter (where opened_at is not null),
    count(*) filter (where clicked_at is not null),
    count(*) filter (where status = 'bounced'),
    count(*)
  into s, d, o, cl, bo, tot
  from email_recipients where campaign_id = p_id;

  select count(*) into un from email_events
    where campaign_id = p_id and type = 'unsubscribe';

  update email_campaigns set
    total_recipients = coalesce(tot,0),
    sent_count = coalesce(s,0),
    delivered_count = coalesce(d,0),
    open_count = coalesce(o,0),
    click_count = coalesce(cl,0),
    bounce_count = coalesce(bo,0),
    unsub_count = coalesce(un,0),
    updated_at = now()
  where id = p_id;

  return jsonb_build_object('ok', true);
end; $function$

-- snapshot-fn: email_worker_claim
CREATE OR REPLACE FUNCTION public.email_worker_claim(p_campaign_id bigint, p_batch integer DEFAULT 100, p_lock_seconds integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb; c record;
begin
  select id, subject, html_body, status from email_campaigns
    where id = p_campaign_id into c;
  if c is null then return jsonb_build_object('error', 'not_found'); end if;

  -- Lepas 'sending' yang macet (worker sebelumnya mati di tengah).
  update email_recipients set status = 'pending'
   where campaign_id = p_campaign_id
     and status = 'sending'
     and coalesce(last_attempt_at, created_at) < now() - make_interval(secs => p_lock_seconds);

  -- Klaim atomik: pending → sending, kembalikan baris yang diklaim.
  with claimed as (
    update email_recipients r set
      status = 'sending',
      last_attempt_at = now(),
      retry_count = r.retry_count + 1
    where r.id in (
      select id from email_recipients
       where campaign_id = p_campaign_id and status = 'pending'
       order by id
       limit greatest(1, least(p_batch, 500))
       for update skip locked
    )
    returning r.id, r.uid, r.email, r.retry_count
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'uid', uid, 'email', email, 'retry', retry_count
  )), '[]'::jsonb) into res from claimed;

  update email_campaigns set status = 'sending', updated_at = now()
    where id = p_campaign_id and status in ('queued','sending');

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'subject', c.subject,
    'html_body', c.html_body,
    'recipients', res
  );
end; $function$

-- snapshot-fn: enforce_age_min
CREATE OR REPLACE FUNCTION public.enforce_age_min()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.age = 0 or NEW.age is null then
    NEW.age := 18;
  end if;
  return NEW;
end; $function$

-- snapshot-fn: enforce_chat_block
CREATE OR REPLACE FUNCTION public.enforce_chat_block()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_other uuid;
begin
  -- Lawan bicara diambil dari table (bukan dari payload klien).
  select p2
    into v_other
    from (
      select unnest(pc.participants) as p2
        from public.private_chats pc
       where pc.chat_id = new.chat_id
    ) x
   where p2 <> new.sender_id
   limit 1;

  if v_other is null then
    return new; -- chat tidak ditemukan / bukan 1:1: biarkan policy yang menilai
  end if;

  if exists (
    select 1
      from public.blocks b
     where (b.blocker_id = new.sender_id and b.blocked_id = v_other)
        or (b.blocker_id = v_other and b.blocked_id = new.sender_id)
  ) then
    raise exception 'blocked' using errcode = 'P0001';
  end if;

  return new;
end;
$function$

-- snapshot-fn: enforce_invisible
CREATE OR REPLACE FUNCTION public.enforce_invisible()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (
    select 1 from app_settings s
    where s.id = 'global'
      and s.invisible_enabled = true
      and s.invisible_admin_uid = new.id::text
  ) then
    new.status := 'invisible';
  end if;
  return new;
end;
$function$

-- snapshot-fn: enforce_onboarding_placeholder
CREATE OR REPLACE FUNCTION public.enforce_onboarding_placeholder()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Pola: 'Anon' + 8 hex (id, uppercase) + opsional angka retry (1-5).
  if new.nickname ~ '^Anon[0-9A-F]{8}[0-9]*$' then
    new.needs_onboarding := true;
  end if;
  return new;
end;
$function$

-- snapshot-fn: enforce_storage_photo
CREATE OR REPLACE FUNCTION public.enforce_storage_photo()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.image_path is not null and NEW.image_path <> '' then
    NEW.image_data := '';
  end if;
  return NEW;
end; $function$

-- snapshot-fn: extend_private_room
CREATE OR REPLACE FUNCTION public.extend_private_room(p_room_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  uid uuid := auth.uid(); r record; points_on boolean;
  paid int; bonus_p int; mult int; remaining int; res jsonb;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;

  select points_enabled, room_extend_paid, bonus_price_multiplier
    into points_on, paid, mult from app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'extend');
    remaining := (res->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  update public.rooms
    set expires_at = greatest(coalesce(expires_at, now()), now()) + interval '7 days'
    where id = p_room_id returning expires_at into r.expires_at;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
                            'expires_at', r.expires_at);
end; $function$

-- snapshot-fn: feature_enabled_for
CREATE OR REPLACE FUNCTION public.feature_enabled_for(p_feature text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v boolean;
begin
  select (feature_flags -> p_feature ->> 'published')::boolean
    into v from app_settings where id = 'global';
  if v is true then return true; end if;
  -- Admin selalu boleh (test di build adminProd sebelum publish).
  return coalesce(auth.email(), '') = 'zunixe@gmail.com';
end; $function$

-- snapshot-fn: fix_story_visibility
CREATE OR REPLACE FUNCTION public.fix_story_visibility()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.visibility = 'registered' then
    new.visibility := 'followers';
  end if;
  return new;
end; $function$

-- snapshot-fn: fn_archive_deleted_user
CREATE OR REPLACE FUNCTION public.fn_archive_deleted_user(p_uid uuid, p_reason text, p_claimed_by uuid DEFAULT NULL::uuid, p_claimed_nick text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_nick text; v_email text; v_reg boolean; v_ip text;
  v_brand text; v_model text; v_last timestamptz; v_created timestamptz;
  v_devices jsonb; v_locations jsonb;
begin
  select nickname, email, coalesce(is_registered,false), ip_address,
         last_seen, created_at
    into v_nick, v_email, v_reg, v_ip, v_last, v_created
    from profiles where id = p_uid;

  -- Snapshot device terakhir milik user (sebelum user_devices dihapus).
  select brand, model into v_brand, v_model
    from user_devices
   where user_id = p_uid
   order by last_seen_at desc nulls last
   limit 1;

  -- Arsip SEMUA device user (biasanya <10; cap 50 anti-bloat).
  select coalesce(jsonb_agg(s.obj order by s.seen desc nulls last), '[]'::jsonb)
    into v_devices
    from (
      select jsonb_build_object(
        'install_id', d.install_id,
        'brand', d.brand,
        'model', d.model,
        'os_name', d.os_name,
        'os_version', d.os_version,
        'app_version', d.app_version,
        'ip_address', d.ip_address,
        'last_seen_at', d.last_seen_at,
        'nickname_snapshot', d.nickname_snapshot,
        'is_active', d.is_active
      ) as obj,
      d.last_seen_at as seen
      from public.user_devices d
      where d.user_id = p_uid
      order by d.last_seen_at desc nulls last
      limit 50
    ) s;

  -- Arsip riwayat GPS/IP terakhir (cap 100 terbaru; cukup untuk audit admin).
  select coalesce(jsonb_agg(s.obj order by s.at desc), '[]'::jsonb)
    into v_locations
    from (
      select jsonb_build_object(
        'lat', h.lat,
        'lon', h.lon,
        'source', h.loc_source,
        'at', h.created_at
      ) as obj,
      h.created_at as at
      from public.user_location_history h
      where h.user_id = p_uid
      order by h.created_at desc
      limit 100
    ) s;

  insert into public.deleted_users
    (user_id, nickname, email, is_registered, brand, model, ip_address,
     last_seen_at, created_at, deleted_at, reason, claimed_by, claimed_nick,
     devices, locations)
  values
    (p_uid, coalesce(v_nick,''), v_email, coalesce(v_reg,false),
     coalesce(v_brand,''), coalesce(v_model,''), coalesce(v_ip,''),
     v_last, v_created, now(),
     p_reason, p_claimed_by, p_claimed_nick,
     coalesce(v_devices,'[]'::jsonb), coalesce(v_locations,'[]'::jsonb))
  on conflict (user_id) do nothing;
end;
$function$

-- snapshot-fn: fn_room_role
CREATE OR REPLACE FUNCTION public.fn_room_role(p_uid uuid, p_room_id text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select role from public.room_members
   where user_id = p_uid and room_id = p_room_id
   limit 1;
$function$

-- snapshot-fn: follow_count_sync
CREATE OR REPLACE FUNCTION public.follow_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.profiles p
  set
    followers_count = (
      select count(*) from public.follows f
      join public.profiles fp on fp.id = f.follower_id
      where f.followee_id = p.id and f.follower_id <> p.id
    ),
    following_count = (
      select count(*) from public.follows f
      join public.profiles fe on fe.id = f.followee_id
      where f.follower_id = p.id and f.followee_id <> p.id
    ),
    friends_count = (
      select count(*) from public.follows a
      join public.follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join public.profiles pa on pa.id = a.follower_id
      join public.profiles pb on pb.id = a.followee_id
      where a.follower_id = p.id and a.followee_id <> p.id
    )
  where p.id in (
    coalesce(new.follower_id, old.follower_id),
    coalesce(new.followee_id, old.followee_id)
  );
  return null; -- AFTER trigger, return value diabaikan
end; $function$

-- snapshot-fn: follow_user
CREATE OR REPLACE FUNCTION public.follow_user(p_followee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); nm text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_followee is null or p_followee = me then raise exception 'Invalid target'; end if;
  if not exists (select 1 from profiles where id = p_followee) then
    raise exception 'User not found';
  end if;
  -- Guard sosial anon (bypass: dummy & admin).
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  if exists (select 1 from profiles where id = me and is_registered = false)
     or exists (select 1 from profiles where id = p_followee and is_registered = false) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
  end if;
  insert into follows (follower_id, followee_id) values (me, p_followee)
    on conflict do nothing;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_followee, coalesce(nm, 'Anon'), 'started following you',
    jsonb_build_object('type', 'follow', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'following', true);
end;
$function$

-- snapshot-fn: friend_request_inbox
CREATE OR REPLACE FUNCTION public.friend_request_inbox()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.from_id as uid, p.nickname,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end as avatar,
           p.gender, p.is_registered, fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.from_id
    where fr.to_id = me and fr.status = 'pending'
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: friend_request_inbox_page
CREATE OR REPLACE FUNCTION public.friend_request_inbox_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  res jsonb; me uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit,50), 200));
  v_offset int := greatest(0, coalesce(p_offset,0));
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.from_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.from_id
    where fr.to_id = me and fr.status = 'pending'
    order by fr.created_at desc
    limit v_limit offset v_offset
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: friend_request_outbox
CREATE OR REPLACE FUNCTION public.friend_request_outbox()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.to_id as uid, p.nickname,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end as avatar,
           p.gender, p.is_registered, fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.to_id
    where fr.from_id = me
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: friend_request_outbox_page
CREATE OR REPLACE FUNCTION public.friend_request_outbox_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  res jsonb; me uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit,50), 200));
  v_offset int := greatest(0, coalesce(p_offset,0));
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select fr.id, fr.to_id as uid, p.nickname, p.avatar, p.gender, p.is_registered,
           fr.status, fr.created_at
    from friend_requests fr join profiles p on p.id = fr.to_id
    where fr.from_id = me
    order by fr.created_at desc
    limit v_limit offset v_offset
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: g_cube_consistent
CREATE OR REPLACE FUNCTION public.g_cube_consistent(internal, cube, smallint, oid, internal)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$g_cube_consistent$function$

-- snapshot-fn: g_cube_distance
CREATE OR REPLACE FUNCTION public.g_cube_distance(internal, cube, smallint, oid, internal)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$g_cube_distance$function$

-- snapshot-fn: g_cube_penalty
CREATE OR REPLACE FUNCTION public.g_cube_penalty(internal, internal, internal)
 RETURNS internal
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$g_cube_penalty$function$

-- snapshot-fn: g_cube_picksplit
CREATE OR REPLACE FUNCTION public.g_cube_picksplit(internal, internal)
 RETURNS internal
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$g_cube_picksplit$function$

-- snapshot-fn: g_cube_same
CREATE OR REPLACE FUNCTION public.g_cube_same(cube, cube, internal)
 RETURNS internal
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$g_cube_same$function$

-- snapshot-fn: g_cube_union
CREATE OR REPLACE FUNCTION public.g_cube_union(internal, internal)
 RETURNS cube
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/cube', $function$g_cube_union$function$

-- snapshot-fn: gate_feature
CREATE OR REPLACE FUNCTION public.gate_feature(p_feature text, p_price_feature text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  cfg jsonb; unit_cost int;
  rkey text; already int; bal int; remaining int;
  today date;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  cfg := (select metered_pricing -> coalesce(p_price_feature, p_feature)
            from app_settings where id = 'global');
  if cfg is null then raise exception 'Unknown feature: %', p_feature; end if;
  unit_cost := coalesce((cfg->>'unit_cost')::int, 0);

  today := (now() at time zone 'Asia/Jakarta')::date;
  rkey := p_feature || ':' || today::text;

  select count(*) into already from public.yukcoin_consumptions
    where user_id = me and feature = p_feature and ref_id = rkey;
  if already > 0 then
    return jsonb_build_object('ok', true, 'already', true, 'charged', 0,
      'remaining', public.yukcoin_total(me));
  end if;

  bal := public.yukcoin_total(me);
  if bal < unit_cost then raise exception 'YukCoin tidak cukup'; end if;

  remaining := public.ledger_spend(me, p_feature, unit_cost, rkey);
  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (me, p_feature, unit_cost, rkey,
            jsonb_build_object('date', today, 'daily', true));

  return jsonb_build_object('ok', true, 'already', false, 'charged', unit_cost,
    'remaining', remaining);
end; $function$

-- snapshot-fn: gc_to_sec
CREATE OR REPLACE FUNCTION public.gc_to_sec(double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN CASE WHEN ($1 < '0'::double precision) THEN '0'::double precision WHEN (($1 / earth()) > pi()) THEN ('2'::double precision * earth()) ELSE (('2'::double precision * earth()) * sin(($1 / ('2'::double precision * earth())))) END

-- snapshot-fn: geo_distance
CREATE OR REPLACE FUNCTION public.geo_distance(point, point)
 RETURNS double precision
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/earthdistance', $function$geo_distance$function$

-- snapshot-fn: get_chat_messages
CREATE OR REPLACE FUNCTION public.get_chat_messages(p_chat_id text, p_before_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid:=auth.uid(); ok bool;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select exists(select 1 from public.private_chats where chat_id=p_chat_id and participants @> array[me]) into ok;
  if not ok then raise exception 'Forbidden'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc),'[]'::jsonb)
          from (select * from public.private_messages where chat_id=p_chat_id and (p_before_id is null or id < p_before_id) order by created_at desc limit least(p_limit,100)) m);
end; $function$

-- snapshot-fn: get_data_sizes
CREATE OR REPLACE FUNCTION public.get_data_sizes()
 RETURNS TABLE(data_type text, total_bytes bigint, row_count bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT 'text', COALESCE(SUM(pg_column_size(text)), 0), COUNT(*) FROM (SELECT text FROM messages WHERE text != '' UNION ALL SELECT text FROM private_messages WHERE text != '') t UNION ALL SELECT 'image', COALESCE(SUM(pg_column_size(image_data)), 0), COUNT(*) FROM (SELECT image_data FROM messages WHERE image_data != '' UNION ALL SELECT image_data FROM private_messages WHERE image_data != '') i; $function$

-- snapshot-fn: get_feature_flags
CREATE OR REPLACE FUNCTION public.get_feature_flags()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return (select coalesce(feature_flags, '{}'::jsonb) from app_settings where id = 'global');
end; $function$

-- snapshot-fn: get_last_messages
CREATE OR REPLACE FUNCTION public.get_last_messages(chat_ids text[])
 RETURNS TABLE(chat_id text, text text, type text, created_at timestamp with time zone)
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT ON (pm.chat_id)
      pm.chat_id,
          pm.text,
              pm.type,
                  pm.created_at
                    FROM private_messages pm
                      WHERE pm.chat_id = ANY(chat_ids)
                        ORDER BY pm.chat_id, pm.created_at DESC;
                        $function$

-- snapshot-fn: get_ledger_history
CREATE OR REPLACE FUNCTION public.get_ledger_history(row_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select id, bucket, type, amount, ref_id, metadata, created_at
    from coin_ledger where user_id = auth.uid()
    order by created_at desc limit greatest(1, least(row_limit, 500))
  ) x;
  return res;
end; $function$

-- snapshot-fn: get_message_counts
CREATE OR REPLACE FUNCTION public.get_message_counts(chat_ids text[])
 RETURNS TABLE(chat_id text, cnt bigint)
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
                          SELECT pm.chat_id, COUNT(*) as cnt
                            FROM private_messages pm
                              WHERE pm.chat_id = ANY(chat_ids)
                                GROUP BY pm.chat_id;
                                $function$

-- snapshot-fn: get_my_kyc
CREATE OR REPLACE FUNCTION public.get_my_kyc()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select to_jsonb(x) into res from (
    select id, status, full_name, id_type, id_number,
           birth_date, reject_reason, reviewed_at, created_at
    from kyc_requests where user_id = auth.uid()
    order by created_at desc limit 1
  ) x;
  if res is null then return jsonb_build_object('status', 'none'); end if;
  return res;
end; $function$

-- snapshot-fn: get_my_topup_orders
CREATE OR REPLACE FUNCTION public.get_my_topup_orders(row_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select id, package_id, coins, price_idr, status, created_at, paid_at
    from topup_orders where user_id = auth.uid()
    order by created_at desc limit greatest(1, least(row_limit, 100))
  ) x;
  return res;
end; $function$

-- snapshot-fn: get_my_withdrawals
CREATE OR REPLACE FUNCTION public.get_my_withdrawals()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
  from (
    select id, coin_amount, payout_idr, rate, status, pay_method,
           pay_account, pay_holder, admin_note, tx_id, created_at, reviewed_at
    from withdrawal_requests where user_id = auth.uid()
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: get_online_users
CREATE OR REPLACE FUNCTION public.get_online_users(p_country text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rows jsonb;
  v_me uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
  v_bypass boolean;
begin
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;

  -- Bypass admin dicek SEKALI (dulu dicek di dalam privacy_can_view 800x).
  v_bypass :=
    coalesce(
      (select privacy_bypass_enabled from public.app_settings where id = 'global'),
      false
    )
    and coalesce(auth.email(), '') = 'zunixe@gmail.com';

  with candidates as (
    select
      p.id, p.nickname, p.gender, p.age, p.country, p.city, p.status, p.avatar,
      p.is_registered, p.last_seen, p.about,
      p.friends_count, p.followers_count,
      coalesce(p.presence_visibility, 'nobody')      as presence_vis,
      coalesce(p.last_seen_visibility, 'nobody')     as seen_vis,
      coalesce(p.profile_photo_visibility, 'nobody') as photo_vis,
      coalesce(p.about_visibility, 'nobody')         as about_vis
    from public.profiles p
    where p.id <> v_me
      and p.status in ('online', 'idle')
      and p.last_seen >= now() - interval '30 minutes'
      and (p_country is null or p.country = p_country)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_me)
      )
    order by p.last_seen desc
    limit p_limit
  ),
  -- Foto: mitra chat private (1 query utk semua kandidat, bukan per-row).
  chat_partners as (
    select distinct c2.uid
    from public.private_chats c
    cross join lateral unnest(c.participants) as c2(uid)
    where c.participants @> array[v_me]::uuid[]
  ),
  -- Foto: anggota room/grup sama (1 query).
  room_mates as (
    select distinct b.user_id as uid
    from public.room_members a
    join public.room_members b on b.room_id = a.room_id
    where a.user_id = v_me
  ),
  -- Exclusions per (owner, field) untuk semua kandidat (1 query).
  excl as (
    select e.owner_id, e.field
    from public.profile_privacy_exclusions e
    where e.excluded_uid = v_me
  ),
  -- Status friend (mutual follow) untuk semua kandidat (1 query).
  friends as (
    select f1.followee_id as uid
    from public.follows f1
    join public.follows f2
      on f1.followee_id = f2.follower_id
     and f1.follower_id = f2.followee_id
    where f1.follower_id = v_me
  ),
  resolved as (
    select
      s.*,
      (v_bypass
        or s.id in (select uid from friends))            as is_friend,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'presence')      as excl_presence,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'last_seen')     as excl_seen,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'profile_photo') as excl_photo,
      exists (select 1 from excl e
               where e.owner_id = s.id and e.field = 'about')         as excl_about,
      (s.id in (select uid from chat_partners)
        or s.id in (select uid from room_mates))         as photo_partner
    from candidates s
  ),
  flags as (
    select
      r.*,
      -- presence
      (v_bypass or r.presence_vis = 'everyone'
        or (r.presence_vis in ('friends','friends_except') and r.is_friend
            and (r.presence_vis = 'friends' or not r.excl_presence))
        or (r.presence_vis = 'everyone_except' and not r.excl_presence)
        or (r.presence_vis = 'only' and r.excl_presence)
      ) as presence_ok,
      -- last_seen
      (v_bypass or r.seen_vis = 'everyone'
        or (r.seen_vis in ('friends','friends_except') and r.is_friend
            and (r.seen_vis = 'friends' or not r.excl_seen))
        or (r.seen_vis = 'everyone_except' and not r.excl_seen)
        or (r.seen_vis = 'only' and r.excl_seen)
      ) as seen_ok,
      -- about
      (v_bypass or r.about_vis = 'everyone'
        or (r.about_vis in ('friends','friends_except') and r.is_friend
            and (r.about_vis = 'friends' or not r.excl_about))
        or (r.about_vis = 'everyone_except' and not r.excl_about)
        or (r.about_vis = 'only' and r.excl_about)
      ) as about_ok,
      -- photo: mitra chat/room SELALU boleh; selain itu aturan visibilitas.
      (v_bypass or r.photo_partner or r.photo_vis = 'everyone'
        or (r.photo_vis in ('friends','friends_except') and r.is_friend
            and (r.photo_vis = 'friends' or not r.excl_photo))
        or (r.photo_vis = 'everyone_except' and not r.excl_photo)
        or (r.photo_vis = 'only' and r.excl_photo)
      ) as photo_ok
    from resolved r
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id, 'nickname', f.nickname, 'gender', f.gender, 'age', f.age,
    'country', f.country, 'city', f.city,
    'status', case when f.presence_ok then f.status else 'offline' end,
    'avatar', case when f.photo_ok then f.avatar else '' end,
    'is_registered', f.is_registered,
    'last_seen', case when f.seen_ok then f.last_seen else null end,
    'about', case when f.about_ok then f.about else '' end,
    'friends_count', f.friends_count,
    'followers_count', f.followers_count
  ) order by f.last_seen desc), '[]'::jsonb)
  into rows
  from flags f
  -- Filter presence SAMA seperti sebelumnya (hormati privasi presence).
  where f.presence_ok;

  return rows;
end;
$function$

-- snapshot-fn: get_points_enabled
CREATE OR REPLACE FUNCTION public.get_points_enabled()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v boolean;
begin
  select points_enabled into v from app_settings where id = 'global';
  return coalesce(v, true);
end;
$function$

-- snapshot-fn: get_poll_results
CREATE OR REPLACE FUNCTION public.get_poll_results(p_message_ids bigint[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'counts', (
      select coalesce(jsonb_agg(coalesce(c.n, 0) order by g.i), '[]'::jsonb)
      from generate_series(0, jsonb_array_length(m.poll->'o') - 1) as g(i)
      left join (
        select v.option_idx, count(*)::int as n
        from public.chat_poll_votes v
        where v.message_id = m.id
        group by v.option_idx
      ) c on c.option_idx = g.i
    ),
    'mine', (
      select coalesce(jsonb_agg(v.option_idx order by v.option_idx), '[]'::jsonb)
      from public.chat_poll_votes v
      where v.message_id = m.id and v.user_id = auth.uid()
    ),
    'voters', (
      select count(distinct v.user_id)::int
      from public.chat_poll_votes v where v.message_id = m.id
    )
  )), '[]'::jsonb)
  from public.private_messages m
  join public.private_chats pc on pc.chat_id = m.chat_id
  where m.id = any (p_message_ids)
    and m.type = 'poll'
    and m.poll is not null
    and auth.uid() = any (pc.participants);
$function$

-- snapshot-fn: get_post
CREATE OR REPLACE FUNCTION public.get_post(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_followers uuid[] := '{}';
  v_subs uuid[] := '{}';
  v_blocked uuid[] := '{}';
  result jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_id is null then return null; end if;

  -- Timeline registered-only (ABSOLUT, cermin list_posts):
  -- anon tidak pernah bisa lihat timeline/post (bypass: dummy & admin).
  if exists (
    select 1 from public.profiles p
    where p.id = me and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'ANON_DISABLED';
  end if;

  select coalesce(array_agg(f.followee_id), '{}') into v_followers
  from public.follows f where f.follower_id = me;

  select coalesce(array_agg(s.creator_id), '{}') into v_subs
  from public.subscriptions s
  where s.subscriber_id = me and s.expires_at > now();

  select coalesce(array_agg(
    case when b.blocker_id = me then b.blocked_id else b.blocker_id end
  ), '{}') into v_blocked
  from public.blocks b
  where b.blocker_id = me or b.blocked_id = me;

  select jsonb_build_object(
    'id', v.id,
    'authorId', v.author_id,
    'authorName', v.author_name,
    'authorGender', v.author_gender,
    'text', v.text,
    'imagePath', v.image_path,
    'images', coalesce(v.images, '{}'),
    'imageW', coalesce(v.image_w, 0),
    'imageH', coalesce(v.image_h, 0),
    'imageDims', coalesce(v.image_dims, '[]'::jsonb),
    'imageBlurhashes', coalesce(v.image_blurhashes, '[]'::jsonb),
    'visibility', v.visibility,
    'likeCount', v.like_count,
    'commentCount', v.comment_count,
    'shareCount', v.share_count,
    'isBoosted', v.is_boosted,
    'createdAt', v.created_at,
    'authorAvatar', pr.avatar,
    'isLiked', exists(
      select 1 from public.post_likes pl
      where pl.post_id = v.id and pl.user_id = me),
    'isFollowing', (v.author_id = any(v_followers)),
    'isFriend', exists (
      select 1 from public.follows a
      join public.follows b on a.followee_id = b.follower_id
        and a.follower_id = b.followee_id
      where a.follower_id = me and a.followee_id = v.author_id),
    'country', v.country
  ) into result
  from public.posts v
  left join public.profiles pr on pr.id = v.author_id
  where v.id = p_id
    and (
      v.visibility = 'public'
      or v.author_id = me
      or (v.visibility = 'followers' and v.author_id = any(v_followers))
      or (v.visibility = 'followers' and v.author_id = any(v_subs))
      or (v.visibility = 'subscribers' and v.author_id = any(v_subs))
    )
    and v.author_id <> all(v_blocked);

  return result;
end;
$function$

-- snapshot-fn: get_room_messages
CREATE OR REPLACE FUNCTION public.get_room_messages(p_room_id text, p_before_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc),'[]'::jsonb)
          from (select * from public.messages where room_id=p_room_id and (p_before_id is null or id < p_before_id) order by created_at desc limit least(p_limit,100)) m);
end; $function$

-- snapshot-fn: get_room_poll_results
CREATE OR REPLACE FUNCTION public.get_room_poll_results(p_message_ids bigint[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'counts', (
      select coalesce(jsonb_agg(coalesce(c.n, 0) order by g.i), '[]'::jsonb)
      from generate_series(0, jsonb_array_length(m.poll->'o') - 1) as g(i)
      left join (
        select v.option_idx, count(*)::int as n
        from public.room_poll_votes v
        where v.message_id = m.id
        group by v.option_idx
      ) c on c.option_idx = g.i
    ),
    'mine', (
      select coalesce(jsonb_agg(v.option_idx order by v.option_idx), '[]'::jsonb)
      from public.room_poll_votes v
      where v.message_id = m.id and v.user_id = auth.uid()
    ),
    'voters', (
      select count(distinct v.user_id)::int
      from public.room_poll_votes v where v.message_id = m.id
    )
  )), '[]'::jsonb)
  from public.messages m
  where m.id = any (p_message_ids)
    and m.type = 'poll'
    and m.poll is not null
    and (
      (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
      or not exists (
        select 1 from public.rooms r
        where r.id = m.room_id and r.is_private = true
      )
      or exists (
        select 1 from public.room_members mm
        where mm.room_id = m.room_id and mm.user_id = auth.uid()
      )
    );
$function$

-- snapshot-fn: get_share_url
CREATE OR REPLACE FUNCTION public.get_share_url()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(share_url, 'https://apkpure.com/chatyuk/com.chatyuk.chatyuk')
  from app_settings where id = 'global';
$function$

-- snapshot-fn: get_table_sizes
CREATE OR REPLACE FUNCTION public.get_table_sizes()
 RETURNS TABLE(table_name text, table_size text, index_size text, total_size text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT schemaname || '.' || tablename, pg_size_pretty(pg_table_size(schemaname || '.' || tablename)), pg_size_pretty(pg_indexes_size(schemaname || '.' || tablename)), pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename))
    FROM pg_tables WHERE schemaname = 'public'
      ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
      $function$

-- snapshot-fn: get_user_photos_access
CREATE OR REPLACE FUNCTION public.get_user_photos_access(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  points_on boolean;
  arr jsonb := '[]'::jsonb;
  rec record;
  idx int := 0;
  is_unlocked boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';

  for rec in
    select id, photo, photo_preview, created_at
    from user_photos where user_id = p_user_id
    order by created_at asc
  loop
    -- Akses: sistem koin mati → semua terbuka. Pemilik sendiri → terbuka.
    -- Index 0 → terbuka. Sudah beli permanen → terbuka.
    is_unlocked := (points_on is false)
                or (me = p_user_id)
                or (idx = 0)
                or exists (select 1 from photo_unlocks
                           where viewer_id = me and photo_id = rec.id);

    arr := arr || jsonb_build_object(
      'id', rec.id,
      'unlocked', is_unlocked,
      -- Foto asli hanya dikirim bila terbuka; jika terkunci kirim preview blur.
      'photo', case when is_unlocked then rec.photo else coalesce(rec.photo_preview, '') end,
      'preview', coalesce(rec.photo_preview, ''),
      'created_at', rec.created_at
    );
    idx := idx + 1;
  end loop;

  return arr;
end; $function$

-- snapshot-fn: get_wallet
CREATE OR REPLACE FUNCTION public.get_wallet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b int; t int; e int;
begin
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = auth.uid();
  return jsonb_build_object(
    'bonus', b, 'topup', t, 'earned', e,
    'total', b + t + e,
    'withdrawable', e
  );
end; $function$

-- snapshot-fn: get_yukcoin
CREATE OR REPLACE FUNCTION public.get_yukcoin()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  e int; b int;
begin
  if me is null then
    return jsonb_build_object('total', 0, 'bonus', 0, 'earned', 0);
  end if;
  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = me;
  return jsonb_build_object('total', (e + b), 'bonus', b, 'earned', e);
end; $function$

-- snapshot-fn: grant_broadcast
CREATE OR REPLACE FUNCTION public.grant_broadcast(p_room_id text, p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE actor_role text;
BEGIN
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  IF actor_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF public.fn_room_role(p_uid, p_room_id) IS NULL THEN RAISE EXCEPTION 'Target not a member'; END IF;
  UPDATE public.room_members SET broadcast_granted = true WHERE room_id = p_room_id AND user_id = p_uid;
END;
$function$

-- snapshot-fn: handle_new_private_message
CREATE OR REPLACE FUNCTION public.handle_new_private_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  receiver uuid;
  unread jsonb := '{}'::jsonb;
  lastread jsonb := '{}'::jsonb;
begin
  select p2 into receiver from (
    select unnest(participants) as p2 from public.private_chats where chat_id = new.chat_id
  ) x where p2 <> new.sender_id limit 1;
  if receiver is null then return new; end if;

  select coalesce(unread_counts, '{}'::jsonb) into unread from public.private_chats where chat_id = new.chat_id;
  if unread is null then unread := '{}'::jsonb; end if;
  unread := jsonb_set(unread, array[receiver::text], to_jsonb(coalesce((unread->>receiver::text)::int, 0) + 1), true);

  select coalesce(last_read_at, '{}'::jsonb) into lastread from public.private_chats where chat_id = new.chat_id;
  if lastread is null then lastread := '{}'::jsonb; end if;

  update public.private_chats set
    last_message = case
      when new.type = 'image' then '[Foto]'
      when new.type = 'view_once' then '[Foto]'
      when new.type = 'coin' then '[Koin]'
      when new.type = 'gift' then '[Hadiah]'
      -- 2026-10-18: tipe ber-teks kosong dulu jatuh ke else ('') → daftar
      -- chat tampil "Belum ada pesan". Video BERCAPTION tetap pakai caption.
      when new.type = 'sticker' then '[Stiker]'
      when new.type = 'voice' then '[Pesan suara]'
      when new.type in ('video','video_once','video_once_expired')
        and coalesce(new.text,'') = '' then '[Video]'
      else new.text end,
    last_message_at = now(),
    last_sender_id = new.sender_id,
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $function$

-- snapshot-fn: handle_new_user_profile
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- SEMUA user (anon & registered) WAJIB isi nickname sendiri.
  -- Tidak ada baris profil yang dibuat otomatis di sini.
  return new;
end;
$function$

-- snapshot-fn: has_password
CREATE OR REPLACE FUNCTION public.has_password(p_uid uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select exists (select 1 from auth.users where id = coalesce(p_uid, auth.uid()) and encrypted_password is not null and encrypted_password <> '') $function$

-- snapshot-fn: housekeeping_tick
CREATE OR REPLACE FUNCTION public.housekeeping_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_idle   int := -1;
  v_voice  int := -1;
  v_stale  int := -1;
  v_cron   int := 0;
begin
  begin
    v_idle := public.presence_idle_tick();
  exception when others then null;
  end;
  begin
    v_stale := public.presence_stale_offline(30);
  exception when others then null;
  end;
  begin
    v_voice := public.room_voice_sweep();
  exception when others then null;
  end;
  begin
    delete from public.room_signals
     where created_at < now() - interval '2 minutes';
  exception when others then null;
  end;
  begin
    delete from public.room_broadcasters
     where started_at < now() - interval '2 minutes';
    update public.rooms r
       set live_uid = null, live_started_at = null
     where r.live_uid is not null
       and not exists (
         select 1 from public.room_broadcasters rb
         where rb.room_id = r.id and rb.user_id = r.live_uid
       );
  exception when others then null;
  end;
  begin
    delete from cron.job_run_details
     where start_time < now() - interval '7 days';
    get diagnostics v_cron = row_count;
  exception when others then null;
  end;
  return jsonb_build_object(
    'presence_idle', v_idle, 'presence_stale_offline', v_stale,
    'voice_sweep', v_voice, 'cron_purged', v_cron
  );
end;
$function$

-- snapshot-fn: increment_unread
CREATE OR REPLACE FUNCTION public.increment_unread(chat_id text, receiver_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ declare unread jsonb; begin select coalesce(unread_counts,'{}'::jsonb) into unread from public.private_chats where chat_id=increment_unread.chat_id; unread:=jsonb_set(unread, array[receiver_id::text], to_jsonb(coalesce((unread->>receiver_id::text)::int,0)+1), true); update public.private_chats set unread_counts=unread where chat_id=increment_unread.chat_id; end; $function$

-- snapshot-fn: invite_to_room
CREATE OR REPLACE FUNCTION public.invite_to_room(p_room_id text, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  my_role text;
  r record;
  member_count int;
  inviter_name text;
  room_name text;
  v_title text;
  v_body text;
  was_member boolean;
  rec record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_uid is null or p_uid = me then raise exception 'Invalid target'; end if;

  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if not r.is_private then raise exception 'Bukan grup private'; end if;
  if r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;

  my_role := public.fn_room_role(me, p_room_id);
  if my_role not in ('owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  if not exists (select 1 from public.profiles where id = p_uid) then
    raise exception 'User not found';
  end if;

  select count(*) into member_count
    from public.room_members where room_id = p_room_id;
  if member_count >= coalesce(r.max_members, 20)
     and not exists (
       select 1 from public.room_members
       where room_id = p_room_id and user_id = p_uid
     ) then
    raise exception 'Room full';
  end if;

  -- Sudah member sebelumnya? (agar tidak kirim notif dobel saat re-invite).
  was_member := exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_uid
  );

  insert into public.room_members (room_id, user_id, role)
  values (p_room_id, p_uid, 'member')
  on conflict (room_id, user_id) do nothing;

  -- Bersihkan status kicked lama (re-invite = pintu dibuka lagi).
  delete from public.room_join_requests
   where room_id = p_room_id and user_id = p_uid;

  -- ── Push notifikasi ke yang diundang (hanya bila BARU jadi member). ──
  if not was_member then
    begin
      select coalesce(nullif(nickname,''), 'Seseorang') into inviter_name
        from public.profiles where id = me;
      inviter_name := coalesce(inviter_name, 'Seseorang');
      room_name := coalesce(nullif(r.name,''), 'Grup');
      v_title := room_name;
      v_body := inviter_name || ' mengundangmu ke grup ' || room_name;

      -- Utamakan user_devices aktif (multi-device); fallback profiles.fcm_token.
      for rec in
        select d.fcm_token as token
          from public.user_devices d
         where d.user_id = p_uid
           and d.is_active = true
           and coalesce(d.fcm_token,'') <> ''
      loop
        begin
          perform net.http_post(
            url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'x-app-secret', (select app_shared_secret from app_settings where id = 'global')
            ),
            body := jsonb_build_object(
              'token', rec.token,
              'title', v_title,
              'body', v_body,
              'data', jsonb_build_object(
                'type', 'room_invite',
                'toUid', p_uid,
                'roomId', p_room_id,
                'roomName', room_name,
                'otherUid', me,
                'otherName', inviter_name,
                'message', v_body
              )
            )
          );
        exception when others then null;
        end;
      end loop;

      -- Fallback klien lama (tanpa baris user_devices).
      if not exists (
        select 1 from public.user_devices d
         where d.user_id = p_uid and d.is_active = true
           and coalesce(d.fcm_token,'') <> ''
      ) then
        for rec in
          select p.fcm_token as token
            from public.profiles p
           where p.id = p_uid and coalesce(p.fcm_token,'') <> ''
        loop
          begin
            perform net.http_post(
              url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
              headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-app-secret', (select app_shared_secret from app_settings where id = 'global')
              ),
              body := jsonb_build_object(
                'token', rec.token,
                'title', v_title,
                'body', v_body,
                'data', jsonb_build_object(
                  'type', 'room_invite',
                  'toUid', p_uid,
                  'roomId', p_room_id,
                  'roomName', room_name,
                  'otherUid', me,
                  'otherName', inviter_name,
                  'message', v_body
                )
              )
            );
          exception when others then null;
          end;
        end loop;
      end if;
    exception when others then null;
    end;
  end if;

  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: is_admin_request
CREATE OR REPLACE FUNCTION public.is_admin_request()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  select coalesce(auth.email(), '') = 'zunixe@gmail.com'
      or auth.role() = 'service_role'
      or (select lower(coalesce(email, '')) from auth.users where id = auth.uid()) = 'zunixe@gmail.com'
$function$

-- snapshot-fn: is_banned_nickname
CREATE OR REPLACE FUNCTION public.is_banned_nickname(p_nickname text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p_nickname is not null and (
    regexp_replace(lower(trim(p_nickname)), '[\s_\-]+', '', 'g') like '%zaini%'
    or regexp_replace(lower(trim(p_nickname)), '[\s_\-]+', '', 'g') like '%hafid%'
  )
$function$

-- snapshot-fn: is_chatyuk_admin
CREATE OR REPLACE FUNCTION public.is_chatyuk_admin(p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from auth.users u
    where u.id = p_uid and u.email = 'zunixe@gmail.com'
  );
$function$

-- snapshot-fn: is_dummy_account
CREATE OR REPLACE FUNCTION public.is_dummy_account(p_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() <> p_uid and coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  return exists (select 1 from public.dummy_accounts where uid = p_uid);
end;
$function$

-- snapshot-fn: is_ghost_mode
CREATE OR REPLACE FUNCTION public.is_ghost_mode()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.ghost_mode_active
    where user_id = auth.uid() and expires_at > now()
  );
$function$

-- snapshot-fn: join_private_room
CREATE OR REPLACE FUNCTION public.join_private_room(p_room_id text, p_password text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  uid uuid := auth.uid(); r record; r_lock record; points_on boolean;
  am_registered boolean; remaining int; charged int := 0;
  paid int; bonus_p int; mult int; tier text; res jsonb;
  member_count int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select * into r_lock from public.rooms where id = p_room_id for update;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.is_private and r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired'; end if;

  if r.owner_id = uid
     or exists (select 1 from public.room_members m where m.room_id = p_room_id and m.user_id = uid) then
    insert into public.room_members (room_id, user_id, role)
    values (p_room_id, uid, case when r.owner_id = uid then 'owner' else 'member' end)
    on conflict (room_id, user_id) do update set role = excluded.role;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
  end if;

  select count(*) into member_count from public.room_members where room_id = p_room_id;
  if member_count >= r.max_members then raise exception 'Room full'; end if;

  if not r.is_private then
    insert into public.room_members (room_id, user_id, role) values (p_room_id, uid, 'member') on conflict do nothing;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
  end if;

  if r.has_password then
    if p_password is null or r.password_hash is null or crypt(p_password, r.password_hash) <> r.password_hash then
      raise exception 'Wrong password'; end if;
  end if;

  if r.approval_required then
    insert into public.room_join_requests (room_id, user_id)
    values (p_room_id, uid)
    on conflict (room_id, user_id) do update set status = 'pending', requested_at = now(), decided_at = null, decided_by = null;
    return jsonb_build_object('ok', true, 'pending', true, 'charged', 0);
  end if;

  -- Auto-join path: private room sekarang GRATIS (tidak ada ledger), sesuai request "bukan mode koin"
  insert into public.room_members (room_id, user_id, role) values (p_room_id, uid, 'member') on conflict do nothing;
  select points into remaining from public.profiles where id = uid;
  insert into public.room_join_requests (room_id, user_id, status, decided_at) values (p_room_id, uid, 'approved', now()) on conflict (room_id, user_id) do update set status='approved', decided_at=now();
  return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
end; $function$

-- snapshot-fn: kick_room_member
CREATE OR REPLACE FUNCTION public.kick_room_member(p_room_id text, p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare actor_role text; target_role text; owner uuid;
begin
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role not in ('owner','admin') then raise exception 'Forbidden'; end if;

  select role into target_role from public.room_members
   where room_id = p_room_id and user_id = p_uid;
  if target_role is null then raise exception 'Not a member'; end if;
  if p_uid = auth.uid() then raise exception 'Cannot kick yourself'; end if;
  if target_role = 'owner' or (target_role = 'admin' and actor_role = 'admin') then
    raise exception 'Forbidden'; end if;

  select owner_id into owner from public.rooms where id = p_room_id;
  delete from public.room_members where room_id = p_room_id and user_id = p_uid;
  -- Tandai kicked → request join berikutnya tetap harus lewat approval.
  insert into public.room_join_requests (room_id, user_id, status, requested_at, decided_at, decided_by)
  values (p_room_id, p_uid, 'kicked', now(), now(), auth.uid())
  on conflict (room_id, user_id) do update
    set status='kicked', requested_at=now(), decided_at=now(), decided_by=auth.uid();
end;
$function$

-- snapshot-fn: latitude
CREATE OR REPLACE FUNCTION public.latitude(earth)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN CASE WHEN ((cube_ll_coord(($1)::cube, 3) / earth()) < '-1'::double precision) THEN '-90'::double precision WHEN ((cube_ll_coord(($1)::cube, 3) / earth()) > '1'::double precision) THEN '90'::double precision ELSE degrees(asin((cube_ll_coord(($1)::cube, 3) / earth()))) END

-- snapshot-fn: leave_private_room
CREATE OR REPLACE FUNCTION public.leave_private_room(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  actor_role text; successor uuid; live uuid; remaining int;
begin
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role is null then return; end if;

  live := (select live_uid from public.rooms where id = p_room_id);
  if live = auth.uid() then
    update public.rooms set live_uid=null, live_started_at=null where id = p_room_id;
  end if;

  delete from public.room_members where room_id = p_room_id and user_id = auth.uid();

  if actor_role = 'owner' then
    -- Suksesor: admin tertua, kalau tidak ada → member tertua.
    select user_id into successor
      from public.room_members
     where room_id = p_room_id and role in ('admin','member')
     order by case when role='admin' then 0 else 1 end, joined_at asc
     limit 1;
    if successor is not null then
      update public.room_members set role='owner'
       where room_id = p_room_id and user_id = successor;
      update public.rooms set owner_id = successor
       where id = p_room_id;
    else
      -- Kosong → hapus room (cascade members/signals/requests).
      delete from public.rooms where id = p_room_id;
    end if;
  end if;
end;
$function$

-- snapshot-fn: ledger_credit
CREATE OR REPLACE FUNCTION public.ledger_credit(p_user uuid, p_bucket text, p_type text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_amount <= 0 then
    return public.wallet_sync_points(p_user);
  end if;
  insert into coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
    values (p_user, p_bucket, p_type, p_amount, p_ref, coalesce(p_meta,'{}'::jsonb));
  return public.wallet_sync_points(p_user);
end; $function$

-- snapshot-fn: ledger_spend
CREATE OR REPLACE FUNCTION public.ledger_spend(p_user uuid, p_type text, p_amount integer, p_ref text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  b int; t int; e int; need int := p_amount; take int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;

  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = p_user;

  if (b + t + e) < p_amount then
    raise exception 'Not enough points';
  end if;

  -- bonus dulu
  take := least(b, need);
  if take > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'bonus',p_type,-take,p_ref);
    need := need - take;
  end if;
  -- topup
  if need > 0 then
    take := least(t, need);
    if take > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (p_user,'topup',p_type,-take,p_ref);
      need := need - take;
    end if;
  end if;
  -- earned
  if need > 0 then
    take := least(e, need);
    if take > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (p_user,'earned',p_type,-take,p_ref);
      need := need - take;
    end if;
  end if;

  return public.wallet_sync_points(p_user);
end; $function$

-- snapshot-fn: ledger_spend_dual
CREATE OR REPLACE FUNCTION public.ledger_spend_dual(p_user uuid, p_type text, p_paid integer, p_bonus integer, p_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b int; t int; e int; remaining int;
begin
  if p_paid <= 0 and p_bonus <= 0 then
    return jsonb_build_object('tier', 'paid', 'remaining', public.wallet_sync_points(p_user));
  end if;

  -- Coba tier berbayar dulu.
  select coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into t, e from coin_ledger where user_id = p_user;
  if (t + e) >= p_paid then
    remaining := public.ledger_spend_paid(p_user, p_type, p_paid, p_ref);
    return jsonb_build_object('tier', 'paid', 'remaining', remaining);
  end if;

  -- Fallback tier bonus.
  select coalesce(sum(amount) filter (where bucket='bonus'),0) into b
    from coin_ledger where user_id = p_user;
  if b >= p_bonus then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'bonus',p_type,-p_bonus,p_ref);
    remaining := public.wallet_sync_points(p_user);
    return jsonb_build_object('tier', 'bonus', 'remaining', remaining);
  end if;

  raise exception 'Not enough points';
end; $function$

-- snapshot-fn: ledger_spend_paid
CREATE OR REPLACE FUNCTION public.ledger_spend_paid(p_user uuid, p_type text, p_amount integer, p_ref text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t int; e int; need int; take int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;
  select coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into t, e from coin_ledger where user_id = p_user;
  if (t + e) < p_amount then raise exception 'Not enough paid'; end if;

  need := p_amount;
  take := least(t, need);
  if take > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'topup',p_type,-take,p_ref);
    need := need - take;
  end if;
  if need > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'earned',p_type,-need,p_ref);
  end if;
  return public.wallet_sync_points(p_user);
end; $function$

-- snapshot-fn: ledger_spend_topup
CREATE OR REPLACE FUNCTION public.ledger_spend_topup(p_user uuid, p_type text, p_amount integer, p_ref text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;
  select coalesce(sum(amount) filter (where bucket='topup'),0)
    into t from coin_ledger where user_id = p_user;
  if t < p_amount then
    raise exception 'Not enough topup';
  end if;
  insert into coin_ledger(user_id,bucket,type,amount,ref_id)
    values (p_user,'topup',p_type,-p_amount,p_ref);
  return public.wallet_sync_points(p_user);
end; $function$

-- snapshot-fn: list_gifts
CREATE OR REPLACE FUNCTION public.list_gifts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.sort_order), '[]'::jsonb) into res
  from (
    select id, emoji, name_id, name_en, coins, sort_order
    from gift_catalog where active = true
  ) x;
  return res;
end; $function$

-- snapshot-fn: list_my_global_rooms
CREATE OR REPLACE FUNCTION public.list_my_global_rooms(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null and p_uid is distinct from auth.uid() then
    raise exception 'Forbidden: hanya boleh melihat room sendiri'
      using errcode = '42501';
  end if;
  return public.list_my_global_rooms_impl(p_uid);
end;
$function$

-- snapshot-fn: list_my_global_rooms_impl
CREATE OR REPLACE FUNCTION public.list_my_global_rooms_impl(p_uid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.last_at desc nulls last), '[]'::jsonb)
  from (
    select r.id, r.name, r.description, r.icon, r.country, r.category,
           r.is_private, r.owner_id, r.owner_name, r.has_password,
           r.expires_at, r.created_at,
           lm.sender_name as last_sender_name,
           lm.text        as last_text,
           lm.type        as last_type,
           lm.created_at  as last_at,
           (select count(*)::int
              from public.messages mm
             where mm.room_id = r.id
               and coalesce(mm.is_deleted, false) = false
               and mm.created_at > coalesce(
                 (select rr.last_read_at from public.room_reads rr
                   where rr.room_id = r.id and rr.user_id = p_uid),
                 to_timestamp(0))) as unread
      from public.rooms r
      join public.room_reads rd
        on rd.room_id = r.id and rd.user_id = p_uid
      left join lateral (
        select m.sender_name, m.text, m.type, m.created_at
          from public.messages m
         where m.room_id = r.id
           and coalesce(m.is_deleted, false) = false
         order by m.created_at desc
         limit 1
      ) lm on true
     where r.is_private = false
       and (r.expires_at is null or r.expires_at > now())
  ) t;
$function$

-- snapshot-fn: list_my_groups
CREATE OR REPLACE FUNCTION public.list_my_groups(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null and p_uid is distinct from auth.uid() then
    raise exception 'Forbidden: hanya boleh melihat grup sendiri'
      using errcode = '42501';
  end if;
  return public.list_my_groups_impl(p_uid);
end;
$function$

-- snapshot-fn: list_my_groups_impl
CREATE OR REPLACE FUNCTION public.list_my_groups_impl(p_uid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
  from (
    select r.*,
           lm.sender_name as last_sender_name,
           lm.text        as last_text,
           lm.type        as last_type,
           lm.created_at  as last_at,
           (select count(*)::int
              from public.messages mm
             where mm.room_id = r.id
               and coalesce(mm.is_deleted, false) = false
               and mm.created_at > coalesce(
                 (select rr.last_read_at from public.room_reads rr
                   where rr.room_id = r.id and rr.user_id = p_uid),
                 to_timestamp(0))) as unread
      from public.rooms r
      left join lateral (
        select m.sender_name, m.text, m.type, m.created_at
          from public.messages m
         where m.room_id = r.id
           and coalesce(m.is_deleted, false) = false
         order by m.created_at desc
         limit 1
      ) lm on true
     where r.is_private = true
       and exists (
         select 1 from public.room_members mb
          where mb.room_id = r.id and mb.user_id = p_uid
       )
  ) t;
$function$

-- snapshot-fn: list_post_comments
CREATE OR REPLACE FUNCTION public.list_post_comments(p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); rows jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'postId', c.post_id,
      'authorId', c.author_id,
      'authorName', c.author_name,
      'authorGender', coalesce(pr.gender, ''),
      'authorAvatar', coalesce(pr.avatar, ''),
      'text', c.text,
      'likeCount', c.like_count,
      'shareCount', c.share_count,
      'parentId', c.parent_id,
      'createdAt', c.created_at,
      'isLiked', exists (select 1 from public.comment_likes cl
                          where cl.comment_id = c.id and cl.user_id = me)
    ) order by c.created_at
  ), '[]'::jsonb) into rows
  from public.post_comments c
  left join public.profiles pr on pr.id = c.author_id
  where c.post_id = p_post_id;
  return rows;
end; $function$

-- snapshot-fn: list_posts
CREATE OR REPLACE FUNCTION public.list_posts(p_scope text DEFAULT 'all'::text, p_limit integer DEFAULT 30, p_cursor timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_boosted boolean DEFAULT false, p_country text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  rows jsonb;
  v_followers uuid[] := '{}';
  v_subs uuid[] := '{}';
  v_blocked uuid[] := '{}';
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Timeline registered-only (ABSOLUT, tak tergantung toggle):
  -- anon tidak pernah bisa lihat timeline/post (bypass: dummy & admin).
  if exists (
    select 1 from public.profiles p
    where p.id = me and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'ANON_DISABLED';
  end if;
  if p_scope not in ('all','following','mine') then p_scope := 'all'; end if;
  p_limit := least(coalesce(p_limit, 30), 50);

  -- Ambil set relasi SEKALI (index-supported, 1 query masing-masing)
  -- daripada EXISTS per baris posts.
  select coalesce(array_agg(f.followee_id), '{}') into v_followers
  from public.follows f where f.follower_id = me;

  select coalesce(array_agg(s.creator_id), '{}') into v_subs
  from public.subscriptions s
  where s.subscriber_id = me and s.expires_at > now();

  select coalesce(array_agg(
    case when b.blocker_id = me then b.blocked_id else b.blocker_id end
  ), '{}') into v_blocked
  from public.blocks b
  where b.blocker_id = me or b.blocked_id = me;

  with visible as (
    select p.*
    from public.posts p
    where
      (p_cursor is null
        or p.is_boosted < p_cursor_boosted
        or (p.is_boosted = p_cursor_boosted and p.created_at < p_cursor))
      and (
        p.visibility = 'public'
        or p.author_id = me
        or (p.visibility = 'followers' and p.author_id = any(v_followers))
        or (p.visibility = 'followers' and p.author_id = any(v_subs))
        or (p.visibility = 'subscribers' and p.author_id = any(v_subs))
      )
      and p.author_id <> all(v_blocked)
      and (
        p_scope = 'all'
        or (p_scope = 'mine' and p.author_id = me)
        or (p_scope = 'following' and p.author_id = any(v_followers))
      )
    order by p.is_boosted desc, p.created_at desc
    limit p_limit
  )
  select jsonb_agg(
    jsonb_build_object(
      'id', v.id,
      'authorId', v.author_id,
      'authorName', v.author_name,
      'authorGender', v.author_gender,
      'text', v.text,
      'imagePath', v.image_path,
      'images', coalesce(v.images, '{}'),
      'imageW', coalesce(v.image_w, 0),
      'imageH', coalesce(v.image_h, 0),
      'imageDims', coalesce(v.image_dims, '[]'::jsonb),
      'imageBlurhashes', coalesce(v.image_blurhashes, '[]'::jsonb),
      'visibility', v.visibility,
      'likeCount', v.like_count,
      'commentCount', v.comment_count,
      'shareCount', v.share_count,
      'isBoosted', v.is_boosted,
      'createdAt', v.created_at,
      'authorAvatar', pr.avatar,
      'isLiked', s.is_liked,
      'isFollowing', s.is_following,
      'isFriend', s.is_friend,
      'country', v.country
    )
    order by v.is_boosted desc, v.created_at desc
  )
  into rows
  from visible v
  left join public.profiles pr on pr.id = v.author_id
  left join lateral (
    select
      exists (select 1 from public.post_likes pl where pl.post_id = v.id and pl.user_id = me) as is_liked,
      (v.author_id = any(v_followers)) as is_following,
      exists (
        select 1 from public.follows a
        join public.follows b on a.followee_id = b.follower_id and a.follower_id = b.followee_id
        where a.follower_id = me and a.followee_id = v.author_id) as is_friend
  ) s on true;

  return jsonb_build_object('posts', coalesce(rows, '[]'::jsonb));
end;
$function$

-- snapshot-fn: list_room_explore
CREATE OR REPLACE FUNCTION public.list_room_explore(p_country text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with online as (
    select room_id, count(*)::int as cnt
    from public.room_presence
    where joined_at > now() - interval '10 minutes'
    group by room_id
  ),
  members as (
    select room_id, count(*)::int as cnt
    from public.room_members
    group by room_id
  ),
  lastmsg as (
    select distinct on (room_id) room_id, sender_name, text, type, created_at
    from public.messages
    where coalesce(is_deleted, false) = false
    order by room_id, created_at desc
  ),
  reads as (
    select room_id, last_read_at
    from public.room_reads
    where user_id = auth.uid()
  )
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.online_count desc, t.last_at desc nulls last),
    '[]'::jsonb)
  from (
    select r.id, r.name, r.description, r.icon, r.country, r.category,
           r.is_private, r.owner_id, r.owner_name, r.has_password,
           r.expires_at, r.created_at,
           -- Live HANYA grup (is_private + live_uid). Global tidak pernah Live.
           (r.is_private and r.live_uid is not null) as is_live,
           coalesce(m.cnt, 0) as member_count,
           coalesce(o.cnt, 0) as online_count,
           lm.sender_name as last_sender_name,
           lm.text as last_text,
           lm.type as last_type,
           lm.created_at as last_at,
           (select count(*)::int
            from public.messages mm
            where mm.room_id = r.id
              and coalesce(mm.is_deleted, false) = false
              and mm.created_at > coalesce(
                (select rr.last_read_at from reads rr where rr.room_id = r.id),
                to_timestamp(0))) as unread
    from public.rooms r
    left join members m on m.room_id = r.id
    left join online o on o.room_id = r.id
    left join lastmsg lm on lm.room_id = r.id
    where r.country = p_country
      -- PEMISAH: explore = GLOBAL saja. Grup tampil di tab Grup.
      and r.is_private = false
      and (r.expires_at is null or r.expires_at > now() or r.owner_id = auth.uid())
    order by o.cnt desc nulls last, lm.created_at desc nulls last
    limit 200
  ) t;
$function$

-- snapshot-fn: list_room_join_requests
CREATE OR REPLACE FUNCTION public.list_room_join_requests(p_room_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', q.user_id, 'nickname', q.nickname,
           'requested_at', q.requested_at
         ) order by q.requested_at asc), '[]'::jsonb)
    from (
      select j.user_id, coalesce(pr.nickname,'User') as nickname, j.requested_at
        from public.room_join_requests j
        left join public.profiles pr on pr.id = j.user_id
       where j.room_id = p_room_id and j.status = 'pending'
       order by j.requested_at asc
    ) q;
$function$

-- snapshot-fn: list_room_members_v2
CREATE OR REPLACE FUNCTION public.list_room_members_v2(p_room_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', m.user_id, 'nickname', coalesce(pr.nickname,'User'),
           'role', m.role, 'joined_at', m.joined_at,
           'broadcast_granted', m.broadcast_granted,
           'status', pr.status, 'last_seen', pr.last_seen,
           'gender', pr.gender
         ) ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
                    pr.nickname), '[]'::jsonb)
    FROM public.room_members m
    LEFT JOIN public.profiles pr ON pr.id = m.user_id
   WHERE m.room_id = p_room_id;
$function$

-- snapshot-fn: list_topup_packages
CREATE OR REPLACE FUNCTION public.list_topup_packages()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select coalesce(jsonb_agg(x order by x.sort_order), '[]'::jsonb) into res
  from (
    select id, coins, price_idr, bonus_label, sort_order, play_product_id
    from topup_packages where active = true
  ) x;
  return res;
end; $function$

-- snapshot-fn: ll_to_earth
CREATE OR REPLACE FUNCTION public.ll_to_earth(double precision, double precision)
 RETURNS earth
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN (cube(cube(cube(((earth() * cos(radians($1))) * cos(radians($2)))), ((earth() * cos(radians($1))) * sin(radians($2)))), (earth() * sin(radians($1)))))::earth

-- snapshot-fn: longitude
CREATE OR REPLACE FUNCTION public.longitude(earth)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN degrees(atan2(cube_ll_coord(($1)::cube, 2), cube_ll_coord(($1)::cube, 1)))

-- snapshot-fn: mark_chat_read
CREATE OR REPLACE FUNCTION public.mark_chat_read(p_chat_id text, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  receipts_on boolean;
begin
  if me is null or p_uid <> me then raise exception 'Unauthorized'; end if;
  if not exists (
    select 1 from public.private_chats c
    where c.chat_id = p_chat_id and me = any(c.participants)
  ) then
    raise exception 'Unauthorized';
  end if;

  receipts_on := coalesce(
    (select read_receipts_enabled from public.profiles where id = me), true);

  update public.private_chats
  set unread_counts = jsonb_set(
        coalesce(unread_counts, '{}'::jsonb),
        array[p_uid::text], '0'::jsonb, true),
      last_read_at = case
        when receipts_on then jsonb_set(
          coalesce(last_read_at, '{}'::jsonb),
          array[p_uid::text], to_jsonb(now()::text), true)
        else last_read_at
      end
  where chat_id = p_chat_id;

  return jsonb_build_object('ok', true, 'receipts', receipts_on);
end;
$function$

-- snapshot-fn: mark_chats_user_deleted
CREATE OR REPLACE FUNCTION public.mark_chats_user_deleted(p_uid uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_n int := 0;
begin
  if p_uid is null then return 0; end if;

  -- Hapus SELURUH isi percakapan di chat yang melibatkan user ini (kedua
  -- sisi) — termasuk pesan lawan, karena tujuannya menghapus ISI, bukan
  -- sekadar pesan milik user yang pergi.
  delete from public.private_messages pm
   using public.private_chats pc
   where pm.chat_id = pc.chat_id
     and pc.participants @> array[p_uid]::uuid[];

  -- Pertahankan baris chat + pasang penanda; kosongkan metadata preview
  -- supaya tidak ada sisa teks yang bocor ke kartu list.
  --
  -- PENTING: `message_count` SENGAJA tidak dinolkan. Klien menyaring chat
  -- dengan `messageCount > 0` (chat_service_private_chatlist.dart) — kalau
  -- dinolkan, baris ini justru ikut terbuang dari daftar dan label "Akun
  -- dihapus" tidak akan pernah terlihat (membatalkan tujuan fitur).
  update public.private_chats pc
     set deleted_participants = (
           select coalesce(array_agg(distinct x), '{}'::uuid[])
           from unnest(pc.deleted_participants || array[p_uid]) as x
         ),
         last_message = '',
         last_sender_id = null,
         unread_counts = '{}'::jsonb,
         last_read_at = '{}'::jsonb
   where pc.participants @> array[p_uid]::uuid[];
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$

-- snapshot-fn: mark_room_read
CREATE OR REPLACE FUNCTION public.mark_room_read(p_room_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  insert into public.room_reads(user_id, room_id, last_read_at)
  values (uid, p_room_id, now())
  on conflict (user_id, room_id) do update set last_read_at = now();
  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: mark_story_seen
CREATE OR REPLACE FUNCTION public.mark_story_seen(p_story_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  v_author uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  select s.author_id into v_author
  from public.stories s
  where s.id = p_story_id;
  -- Ghost-mode: admin lihat story orang → akui ok TANPA mencatat.
  -- Story milik sendiri tetap dicatat (konsisten dengan bulk).
  if v_author is not null and v_author <> uid and public.is_admin_request() then
    return jsonb_build_object('ok', true);
  end if;
  if exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and s.expires_at > now()
      and public.privacy_can_view(s.author_id, 'story', uid)
      and (
        s.author_id = uid
        or (
          (
            (s.visibility = 'everyone')
            or (s.visibility = 'followers' and exists (
                  select 1 from public.follows f
                  where f.follower_id = uid and f.followee_id = s.author_id))
            or (s.visibility = 'friends' and public._are_friends(uid, s.author_id))
            or (s.visibility = 'registered' and public._viewer_is_registered())
          )
          and not exists (
            select 1 from public.blocks b
            where (b.blocker_id = uid and b.blocked_id = s.author_id)
               or (b.blocker_id = s.author_id and b.blocked_id = uid)
          )
        )
      )
  ) then
    insert into public.story_views (story_id, viewer_id)
    values (p_story_id, uid)
    on conflict (story_id, viewer_id) do nothing;
  end if;
  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: mark_story_seen_bulk
CREATE OR REPLACE FUNCTION public.mark_story_seen_bulk(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  n integer := 0;
  v_is_admin boolean := public.is_admin_request();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_ids is null or array_length(p_ids, 1) is null then return 0; end if;

  insert into public.story_views (story_id, viewer_id)
  select s.id, uid
  from public.stories s
  where s.id = any (p_ids)
    and s.expires_at > now()
    -- Ghost-mode: admin hanya mencatat story milik sendiri.
    and (s.author_id = uid or not v_is_admin)
    -- Privacy story author (sumber kebenaran sama dengan story_slides/tray).
    and public.privacy_can_view(s.author_id, 'story', uid)
    and (
      s.author_id = uid
      or (
        (
          (s.visibility = 'everyone')
          or (s.visibility = 'followers' and exists (
                select 1 from public.follows f
                where f.follower_id = uid and f.followee_id = s.author_id))
          or (s.visibility = 'friends' and public._are_friends(uid, s.author_id))
          or (s.visibility = 'registered' and public._viewer_is_registered())
        )
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = uid and b.blocked_id = s.author_id)
             or (b.blocker_id = s.author_id and b.blocked_id = uid)
        )
      )
    )
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$function$

-- snapshot-fn: metered_pricing_public
CREATE OR REPLACE FUNCTION public.metered_pricing_public()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return (select jsonb_build_object(
    'call_audio_cost_per_min', call_audio_cost_per_min,
    'call_video_cost_per_min', call_video_cost_per_min,
    'call_free_minutes_daily', call_free_minutes_daily,
    'filter_gender_cost', filter_gender_cost,
    'nearby_cost', nearby_cost
  ) from app_settings where id = 'global');
end; $function$

-- snapshot-fn: mute_private_chat
CREATE OR REPLACE FUNCTION public.mute_private_chat(p_chat_id text, p_mute boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  me_text text := me::text;
  r record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into r from public.private_chats where chat_id = p_chat_id;
  if not found then raise exception 'Chat not found'; end if;
  if not exists (select 1 from unnest(r.participants::text[]) as p where p = me_text) then
    raise exception 'Forbidden';
  end if;

  if p_mute then
    update public.private_chats
    set muted_by = array(select distinct unnest(array_append(coalesce(muted_by,'{}'), me_text)))
    where chat_id = p_chat_id;
  else
    update public.private_chats
    set muted_by = array_remove(coalesce(muted_by,'{}'), me_text)
    where chat_id = p_chat_id;
  end if;
  return jsonb_build_object('ok', true, 'muted', p_mute);
end; $function$

-- snapshot-fn: mute_room
CREATE OR REPLACE FUNCTION public.mute_room(p_room_id text, p_mute boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  me_text text := me::text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'Room not found';
  end if;
  if p_mute then
    update public.rooms
    set muted_by = array(select distinct unnest(array_append(coalesce(muted_by,'{}'), me_text)))
    where id = p_room_id;
  else
    update public.rooms
    set muted_by = array_remove(coalesce(muted_by,'{}'), me_text)
    where id = p_room_id;
  end if;
  return jsonb_build_object('ok', true, 'muted', p_mute);
end; $function$

-- snapshot-fn: mute_story_author
CREATE OR REPLACE FUNCTION public.mute_story_author(p_author uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_author is null or p_author = me then
    raise exception 'Invalid author';
  end if;
  if not exists (select 1 from public.profiles where id = p_author) then
    raise exception 'Author not found';
  end if;
  insert into public.story_mutes (muter_id, muted_id)
  values (me, p_author)
  on conflict do nothing;
end; $function$

-- snapshot-fn: my_extra_photo_slots
CREATE OR REPLACE FUNCTION public.my_extra_photo_slots()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select extra from public.photo_slots_unlocked
                    where user_id = auth.uid()), 0);
$function$

-- snapshot-fn: my_photos
CREATE OR REPLACE FUNCTION public.my_photos()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  arr jsonb;
begin
  if me is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',         r.id,
    'unlocked',   true,
    'photo',      r.photo,
    'preview',    coalesce(r.photo_preview, ''),
    'created_at', r.created_at
  ) order by r.created_at asc), '[]'::jsonb) into arr
  from public.user_photos r where r.user_id = me;
  return arr;
end;
$function$

-- snapshot-fn: my_privacy_settings
CREATE OR REPLACE FUNCTION public.my_privacy_settings()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'presence', coalesce(presence_visibility, 'everyone'),
    'last_seen', coalesce(last_seen_visibility, 'everyone'),
    'profile_photo', coalesce(profile_photo_visibility, 'everyone'),
    'about', coalesce(about_visibility, 'everyone'),
    'story', coalesce(story_visibility, 'everyone'),
    'leaderboard', coalesce(leaderboard_visibility, 'everyone'),
    'call', coalesce(call_visibility, 'everyone'),
    'read_receipts', coalesce(read_receipts_enabled, true),
    'exclusions', coalesce((select jsonb_object_agg(field, ids) from (
      select field, jsonb_agg(excluded_uid) as ids
      from profile_privacy_exclusions
      where owner_id = auth.uid()
      group by field
    ) x), '{}'::jsonb)
  )
  from profiles where id = auth.uid();
$function$

-- snapshot-fn: my_share_stats
CREATE OR REPLACE FUNCTION public.my_share_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  return jsonb_build_object(
    'total_clicks', (select count(*) from referral_clicks where sharer_id = me),
    'rewarded_clicks', (select count(*) from referral_clicks where sharer_id = me and rewarded = true),
    'today_rewarded', (select count(*) from referral_clicks
                       where sharer_id = me and rewarded = true
                       and click_day = (now() at time zone 'Asia/Jakarta')::date)
  );
end;
$function$

-- snapshot-fn: my_social_status
CREATE OR REPLACE FUNCTION public.my_social_status(p_other uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  return jsonb_build_object(
    'following', exists(select 1 from follows where follower_id = me and followee_id = p_other),
    'follows_me', exists(select 1 from follows where follower_id = p_other and followee_id = me),
    'friend', exists(select 1 from follows a join follows b
      on a.follower_id = b.followee_id and a.followee_id = b.follower_id
      where a.follower_id = me and a.followee_id = p_other),
    'friend_request_sent', exists(select 1 from friend_requests
      where from_id = me and to_id = p_other and status = 'pending'),
    'friend_request_received', exists(select 1 from friend_requests
      where from_id = p_other and to_id = me and status = 'pending'),
    'subscribed', exists(select 1 from subscriptions
      where subscriber_id = me and creator_id = p_other and expires_at > now()),
    'is_subscribed_to_me', exists(select 1 from subscriptions
      where subscriber_id = p_other and creator_id = me and expires_at > now())
  );
end; $function$

-- snapshot-fn: my_subscriptions
CREATE OR REPLACE FUNCTION public.my_subscriptions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb; me uuid := auth.uid();
begin
  select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
  from (
    select s.creator_id as uid, p.nickname,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end as avatar,
           p.gender, p.is_registered, s.price, s.expires_at
    from subscriptions s join profiles p on p.id = s.creator_id
    where s.subscriber_id = me and s.expires_at > now()
  ) x;
  return coalesce(res, '[]'::jsonb);
end; $function$

-- snapshot-fn: nearby_users
CREATE OR REPLACE FUNCTION public.nearby_users(p_radius_km double precision DEFAULT 10, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(uid uuid, nickname text, gender text, age integer, country text, city text, status text, avatar text, is_registered boolean, last_seen timestamp with time zone, distance_km double precision)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  radius_m double precision;
  v_excl uuid[];
  v_price int;
  v_published boolean;
  v_admin boolean;
  v_today date;
  v_paid int;
  lim int := greatest(1, least(p_limit, 200));
  off int := greatest(0, coalesce(p_offset, 0));
begin
  if me is null then raise exception 'Not authenticated'; end if;

  v_admin := coalesce(auth.email(), '') = 'zunixe@gmail.com';
  select (feature_flags -> 'nearby_paid' ->> 'published')::boolean,
         coalesce(nearby_cost, 25)
    into v_published, v_price
    from app_settings where id = 'global';

  if coalesce(v_published, false) and not v_admin then
    v_today := (now() at time zone 'Asia/Jakarta')::date;
    select count(*) into v_paid from public.yukcoin_consumptions
      where user_id = me and feature = 'nearby'
        and ref_id = 'nearby:' || v_today::text;
    if v_paid = 0 then
      perform public.gate_feature('nearby', 'nearby');
    end if;
  end if;

  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon
    into my_lat, my_lon
  from public.profiles p where p.id = me;

  if my_lat is null or my_lon is null then
    raise exception 'No location';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  return query
  select
    p.id,
    p.nickname,
    p.gender,
    p.age,
    p.country,
    p.city,
    p.status,
    case when public.privacy_can_view(p.id, 'profile_photo', me) then p.avatar else '' end,
    p.is_registered,
    case when public.privacy_can_view(p.id, 'last_seen', me) then p.last_seen else null end,
    (earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) / 1000.0) as distance_km
  from public.profiles p
  where p.id <> me
    and p.lat is not null
    and p.lon is not null
    and p.status in ('online', 'idle')
    and p.last_seen >= now() - interval '30 minutes'
    and public.privacy_can_view(p.id, 'presence', me)
    and not (p.id = any(v_excl))
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    )
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by 11 asc
  limit lim offset off;
end;
$function$

-- snapshot-fn: new_chat_bonus
CREATE OR REPLACE FUNCTION public.new_chat_bonus(other_uid uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: notify_broadcast_started
CREATE OR REPLACE FUNCTION public.notify_broadcast_started()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  b_name text;
  r_name text;
  t text;
  v_uid uuid;
begin
  begin
    select coalesce(nickname, name, 'Anon') into b_name
      from public.profiles where id = new.user_id;
    select name into r_name from public.rooms where id = new.room_id;

    for v_uid in
      select m.user_id
        from public.room_members m
       where m.room_id = new.room_id
         and m.user_id <> new.user_id
    loop
      for t in select public.user_fcm_tokens(v_uid) loop
        insert into public.outbox (type, payload)
        values ('push', jsonb_build_object(
          'endpoint','send-push',
          'token', t,
          'data', jsonb_build_object(
            'type', 'broadcast',
            'roomId', new.room_id,
            'roomName', coalesce(r_name, 'Room'),
            'ownerId', new.user_id,
            'otherUid', new.user_id,
            'otherName', coalesce(b_name, 'Anon')
          )
        ));
      end loop;
    end loop;
  exception when others then
    null;
  end;
  return new;
end; $function$

-- snapshot-fn: notify_call_ended
CREATE OR REPLACE FUNCTION public.notify_call_ended()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rec record;
  v_chat_id text;
  v_name text;
  v_body text;
begin
  -- Hanya transisi pertama dari ringing/answered ke terminal
  if old.status not in ('ringing','answered') then return new; end if;
  if new.status not in ('canceled','missed','declined','ended','busy') then return new; end if;
  -- Idempoten: jika sudah pernah kirim untuk call ini, jangan kirim lagi
  if new.notif_sent_at is not null then return new; end if;

  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' || greatest(new.caller_id::text, new.callee_id::text);
  select nickname into v_name from public.profiles where id = new.caller_id;
  v_name := coalesce(nullif(v_name,''), 'User');
  v_body := case
    when new.status in ('ended','canceled') then 'Call ended'
    when new.status = 'missed' then 'Missed call'
    when new.status = 'declined' then 'Call declined'
    when new.status = 'busy' then 'Busy'
    else 'Call ended'
  end;

  for rec in select public.user_fcm_tokens(new.callee_id) as fcm_token loop
    insert into public.outbox (type, payload)
    values ('push', jsonb_build_object(
      'token', rec.fcm_token,
      'title', v_name,
      'body', v_body,
      'data', jsonb_build_object(
        'type', 'call_ended',
        'toUid', new.callee_id,
        'callId', new.id,
        'chatId', v_chat_id,
        'callerUid', new.caller_id,
        'otherName', v_name
      )
    ));
  end loop;

  -- Tandai sudah dikirim supaya update berikutnya tidak kirim lagi
  new.notif_sent_at := now();
  return new;
exception when others then return new;
end; $function$

-- snapshot-fn: notify_call_ringing
CREATE OR REPLACE FUNCTION public.notify_call_ringing()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare caller_name text; caller_avatar text;
begin
  if new.status <> 'ringing' then return new; end if;
  select nickname, avatar into caller_name, caller_avatar from public.profiles where id = new.caller_id;
  perform public.call_push(new.callee_id, new.id, new.caller_id, coalesce(nullif(caller_name,''), 'User'), new.call_type, coalesce(caller_avatar,''));
  return new;
exception when others then return new;
end; $function$

-- snapshot-fn: notify_contact_online
CREATE OR REPLACE FUNCTION public.notify_contact_online()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  contact_id uuid;
  contact_chat text;
  t text;
begin
  if new.status <> 'online' or old.status = 'online' then return new; end if;
  -- Dummy: bot tidak perlu memberi tahu kontak bahwa ia "online".
  if exists (select 1 from public.dummy_accounts d where d.uid = new.id) then
    return new;
  end if;
  for contact_id, contact_chat in
    select distinct u.uid, (
      select pc.chat_id from public.private_chats pc
      where new.id = any (pc.participants)
        and u.uid = any (pc.participants)
      limit 1
    )
    from (
      -- teman (mutual follow)
      select f1.followee_id as uid
      from public.follows f1
      join public.follows f2
        on f1.followee_id = f2.follower_id
       and f1.follower_id = f2.followee_id
      where f1.follower_id = new.id
      union
      -- follower-ku
      select f.follower_id as uid
      from public.follows f
      where f.followee_id = new.id
      union
      -- pernah 1:1 chat (perilaku lama)
      select distinct u as uid
      from public.private_chats pc
      cross join lateral unnest(pc.participants) as u
      where new.id = any (pc.participants) and u <> new.id
    ) u
    where u.uid <> new.id
      -- skip blokir dua arah (selaras get_online_users)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = u.uid and b.blocked_id = new.id)
           or (b.blocker_id = new.id and b.blocked_id = u.uid)
      )
  loop
    for t in select public.user_fcm_tokens(contact_id) loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
        'endpoint','send-push',
        'token', t,
        'title', coalesce(new.nickname,'Anon'),
        'body', 'is online',
        'data', jsonb_build_object(
          -- coalesce: NULL → String("null") di send-push → klien gagal
          -- bedakan "tanpa chat" (harus string kosong → buka profil).
          'type','online','chatId',coalesce(contact_chat,''),
          'otherUid',new.id,'otherName',coalesce(new.nickname,'Anon')
        )
      ));
    end loop;
  end loop;
  return new;
exception when others then return new;
end;
$function$

-- snapshot-fn: notify_mention_room
CREATE OR REPLACE FUNCTION public.notify_mention_room()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rec record;
  sender_display text;
  sender_avatar text;
  room_name text;
  v_body text;
begin
  begin
    -- Hanya saat ada mention; selain itu trigger tidak melakukan apa pun.
    if new.mentions is null
       or jsonb_typeof(new.mentions) <> 'array'
       or jsonb_array_length(new.mentions) = 0 then
      return new;
    end if;

    select coalesce(nullif(nickname,''), nullif(new.sender_name,''), 'User'), avatar
      into sender_display, sender_avatar
      from public.profiles where id = new.sender_id;
    sender_display := coalesce(sender_display, 'User');

    select coalesce(nullif(name,''), 'Room') into room_name
      from public.rooms where id = new.room_id;
    room_name := coalesce(room_name, 'Room');

    v_body := case
      when new.type in ('image','view_once') then sender_display || ' menyebutmu · [Foto]'
      when new.type = 'voice' then sender_display || ' menyebutmu · [Pesan suara]'
      when new.type = 'gift' then sender_display || ' menyebutmu · [Hadiah]'
      else sender_display || ': ' || left(coalesce(new.text,''), 160)
    end;

    for rec in
      select distinct d.fcm_token as token, (m->>'uid')::uuid as uid
        from jsonb_array_elements(new.mentions) as m
        join public.user_devices d
          on d.user_id = (m->>'uid')::uuid
         and d.is_active = true
         and coalesce(d.fcm_token,'') <> ''
       where (m->>'uid')::uuid <> new.sender_id
    loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
        'token', rec.token,
        'title', room_name,
        'body', v_body,
        'data', jsonb_build_object(
          'type', 'mention',
          'toUid', rec.uid,
          'chatId', new.room_id,
          'roomId', new.room_id,
          'roomName', room_name,
          'otherUid', new.sender_id,
          'otherName', sender_display,
          'avatarUrl', coalesce(sender_avatar,''),
          'message', v_body,
          'body', v_body
        )
      ));
    end loop;

    -- Fallback (klien lama tanpa baris user_devices): profiles.fcm_token.
    if not exists (
      select 1 from public.user_devices d
       join jsonb_array_elements(new.mentions) as m on d.user_id = (m->>'uid')::uuid
       where d.is_active = true and coalesce(d.fcm_token,'') <> ''
    ) then
      for rec in
        select p.fcm_token as token, p.id as uid
          from public.profiles p
          join jsonb_array_elements(new.mentions) as m on p.id = (m->>'uid')::uuid
         where p.id <> new.sender_id and coalesce(p.fcm_token,'') <> ''
      loop
        insert into public.outbox (type, payload)
        values ('push', jsonb_build_object(
          'token', rec.token,
          'title', room_name,
          'body', v_body,
          'data', jsonb_build_object(
            'type', 'mention',
            'toUid', rec.uid,
            'chatId', new.room_id,
            'roomId', new.room_id,
            'roomName', room_name,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'avatarUrl', coalesce(sender_avatar,''),
            'message', v_body,
            'body', v_body
          )
        ));
      end loop;
    end if;
  exception when others then null;
  end;
  return new;
end;
$function$

-- snapshot-fn: notify_online_fanout
CREATE OR REPLACE FUNCTION public.notify_online_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'online' and coalesce(old.status, 'offline') <> 'online' then
    -- Dummy = bot; presence dikelola ai_presence_tick. Fanout ke bot hanya
    -- memicu http_post + outbox tiap 5 menit (beban, bukan value).
    if exists (select 1 from public.dummy_accounts d where d.uid = new.id) then
      return new;
    end if;
    if new.last_online_notified_at is null
       or now() - new.last_online_notified_at > interval '10 minutes' then
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
        headers := jsonb_build_object('Content-Type','application/json'),
        body := jsonb_build_object('type','online','id', new.id::text)
      );
      -- BEFORE trigger: cukup set kolomnya. Dulu ada `UPDATE profiles ...`
      -- nested di AFTER trigger → menulis 2× + memicu ulang semua trigger.
      new.last_online_notified_at := now();
    end if;
  end if;
  return new;
end;
$function$

-- snapshot-fn: notify_post_followers
CREATE OR REPLACE FUNCTION public.notify_post_followers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  author_name text;
  rec record;
  notif_title text;
  notif_body text;
  v_author_dummy boolean;
begin
  -- ambil nama author
  select nickname into author_name from public.profiles where id = new.author_id;
  author_name := coalesce(author_name, 'User');

  -- preview text untuk body notifikasi (potong 80 char)
  notif_body := left(coalesce(new.text, ''), 80);
  if notif_body = '' then
    if new.image_path <> '' then
      notif_body := '[Foto]';
    else
      notif_body := 'membuat postingan baru';
    end if;
  end if;

  notif_title := author_name;
  v_author_dummy := exists (
    select 1 from public.admin_dummy_uids() du where du = new.author_id
  );

  -- Untuk post visibility subscribers -> hanya subscriber aktif
  if new.visibility = 'subscribers' then
    for rec in
      select s.subscriber_id as uid
      from public.subscriptions s
      where s.creator_id = new.author_id
        and s.expires_at > now()
        and s.subscriber_id <> new.author_id
      limit 1000
    loop
      -- skip jika ada block
      if exists (
        select 1 from public.blocks b
        where (b.blocker_id = rec.uid and b.blocked_id = new.author_id)
           or (b.blocker_id = new.author_id and b.blocked_id = rec.uid)
      ) then
        continue;
      end if;

      perform public.social_push(
        rec.uid,
        notif_title,
        notif_body,
        jsonb_build_object(
          'type', 'timeline_post',
          'postId', new.id,
          'authorId', new.author_id,
          'authorName', author_name
        )
      );
    end loop;
  elsif new.visibility = 'followers' then
    -- followers -> hanya follower
    for rec in
      select f.follower_id as uid
      from public.follows f
      where f.followee_id = new.author_id
        and f.follower_id <> new.author_id
      limit 1000
    loop
      if exists (
        select 1 from public.blocks b
        where (b.blocker_id = rec.uid and b.blocked_id = new.author_id)
           or (b.blocker_id = new.author_id and b.blocked_id = rec.uid)
      ) then
        continue;
      end if;

      perform public.social_push(
        rec.uid,
        notif_title,
        notif_body,
        jsonb_build_object(
          'type', 'timeline_post',
          'postId', new.id,
          'authorId', new.author_id,
          'authorName', author_name
        )
      );
    end loop;
  elsif not v_author_dummy then
    -- public (dan fallback) -> SEMUA user, KECUALI bila author dummy
    -- (akun test tak boleh spam user asli): registered, bukan dummy,
    -- bukan exclude, bukan author, tanpa blokir dua arah.
    for rec in
      select p.id as uid
      from public.profiles p
      where p.id <> new.author_id
        and coalesce(p.is_registered, false) = true
        and p.id not in (select du from public.admin_dummy_uids() du)
        and not (p.id = any(coalesce(
          (select array_agg(ae) from public.admin_excluded_uids() ae),
          '{}'::uuid[])))
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = p.id and b.blocked_id = new.author_id)
             or (b.blocker_id = new.author_id and b.blocked_id = p.id)
        )
      limit 2000
    loop
      perform public.social_push(
        rec.uid,
        notif_title,
        notif_body,
        jsonb_build_object(
          'type', 'timeline_post',
          'postId', new.id,
          'authorId', new.author_id,
          'authorName', author_name
        )
      );
    end loop;
  end if;

  return new;
exception when others then
  -- jangan gagalkan insert post jika push gagal
  return new;
end;
$function$

-- snapshot-fn: notify_private_message
CREATE OR REPLACE FUNCTION public.notify_private_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
  sender_avatar text;
  v_body text;
begin
  begin
    if new.type = 'call' then
      if exists (
        select 1 from public.private_messages
        where chat_id = new.chat_id
          and type = 'call'
          and created_at > now() - interval '30 seconds'
          and id <> new.id
      ) then
        return new;
      end if;
      select p into receiver_id from (
        select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
      ) x where x.p <> new.sender_id limit 1;
      if receiver_id is null then return new; end if;
      select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
      sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
      for receiver_token in select public.user_fcm_tokens(receiver_id) loop
        insert into public.outbox (type, payload)
        values ('push', jsonb_build_object(
          'token', receiver_token,
          'title', sender_display,
          'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
          'data', jsonb_build_object(
            'type', 'missed_call',
            'toUid', receiver_id,
            'chatId', new.chat_id,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'callText', coalesce(new.text, 'Missed call'),
            'avatarUrl', coalesce(sender_avatar,''),
            'message', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
            'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab')
          )
        ));
      end loop;
      return new;
    end if;

    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is null then return new; end if;
    select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
    sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
    -- Preview isi: teks (200 char) atau label tipe non-teks.
    v_body := case when new.type in ('image','view_once') then '[Foto]'
                   when new.type in ('video','video_once','video_once_expired')
                     then '[Video]'
                   when new.type = 'voice' then '[Pesan suara]'
                   when new.type = 'coin' then '[Koin]'
                   when new.type = 'gift' then '[Hadiah]'
                   -- 2026-10-18: stiker dulu body kosong; lokasi dulu JSON
                   -- koordinat mentah di notifikasi.
                   when new.type = 'sticker' then '[Stiker]'
                   when new.type = 'location' then '[Lokasi]'
                   else left(coalesce(new.text,''), 200) end;
    for receiver_token in select public.user_fcm_tokens(receiver_id) loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
        'token', receiver_token,
        'title', sender_display,
        'body', v_body,
        'data', jsonb_build_object(
          'type', 'message',
          'toUid', receiver_id,
          'chatId', new.chat_id,
          'otherUid', new.sender_id,
          'otherName', sender_display,
          'avatarUrl', coalesce(sender_avatar,''),
          'message', v_body,
          'body', v_body
        )
      ));
    end loop;
  exception when others then null;
  end;
  return new;
end; $function$

-- snapshot-fn: notify_room_fanout
CREATE OR REPLACE FUNCTION public.notify_room_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','room','id', new.id::text)
  );
  return new;
end; $function$

-- snapshot-fn: notify_timeline_count_fanout
CREATE OR REPLACE FUNCTION public.notify_timeline_count_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(new.like_count,0) = coalesce(old.like_count,0)
     and coalesce(new.comment_count,0) = coalesce(old.comment_count,0)
     and coalesce(new.share_count,0) = coalesce(old.share_count,0) then
    return new;
  end if;
  if new.last_notified_at is null or now() - new.last_notified_at > interval '5 seconds' then
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('type','timeline', 'id', new.id::text)
    );
    update public.posts set last_notified_at = now() where id = new.id;
  end if;
  return new;
end; $function$

-- snapshot-fn: notify_timeline_post_fanout
CREATE OR REPLACE FUNCTION public.notify_timeline_post_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(new.visibility, 'public') <> 'public' then
    return new;
  end if;
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','timeline','id', new.id::text)
  );
  return new;
end;
$function$

-- snapshot-fn: one_time_bonus
CREATE OR REPLACE FUNCTION public.one_time_bonus(action_key text, bonus integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tot int;
begin
  -- No-op: bonus gratis dihapus. Kembalikan saldo apa adanya.
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: phone_verify_confirm
CREATE OR REPLACE FUNCTION public.phone_verify_confirm(p_token text, p_phone text, p_chat_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.phone_verifications%rowtype;
  v_want text;
  v_got text;
begin
  select * into v_row
  from public.phone_verifications
  where token = p_token
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'unknown_token');
  end if;
  if v_row.status = 'verified' then
    return jsonb_build_object('ok', true, 'reason', 'already_verified');
  end if;
  if v_row.expires_at < now() then
    update public.phone_verifications
       set status = 'expired' where id = v_row.id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- Normalisasi: bandingkan digit saja.
  v_want := regexp_replace(coalesce(v_row.phone, ''), '[^0-9]', '', 'g');
  v_got := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');

  -- Bandingkan juga versi tanpa kode negara '0' vs '62' (umum di ID) agar
  -- tidak gagal karena format +62/0. Cocok kalau salah satu suffix 9+ digit
  -- sama.
  if v_want <> v_got then
    if length(v_want) >= 9 and length(v_got) >= 9
       and right(v_want, 9) = right(v_got, 9) then
      -- anggap cocok (suffix sama)
      null;
    else
      update public.phone_verifications
         set attempts = attempts + 1, status = 'failed'
       where id = v_row.id;
      return jsonb_build_object('ok', false, 'reason', 'phone_mismatch');
    end if;
  end if;

  update public.phone_verifications
     set status = 'verified',
         verified_at = now(),
         telegram_chat_id = coalesce(p_chat_id, telegram_chat_id)
   where id = v_row.id;

  update public.profiles
     set phone_verified_at = now()
   where id = v_row.uid;

  return jsonb_build_object('ok', true, 'reason', 'verified', 'uid', v_row.uid);
end;
$function$

-- snapshot-fn: phone_verify_start
CREATE OR REPLACE FUNCTION public.phone_verify_start()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_recent int;
  v_token text;
  v_expires timestamptz := now() + interval '15 minutes';
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select phone into v_phone from public.profiles where id = v_uid;
  if v_phone is null or v_phone = '' then
    raise exception 'phone_empty';
  end if;

  -- Rate limit: maksimal 3 permintaan dalam 1 jam terakhir.
  select count(*) into v_recent
  from public.phone_verifications
  where uid = v_uid and created_at > now() - interval '1 hour';
  if v_recent >= 3 then
    raise exception 'rate_limited';
  end if;

  -- Batalkan token pending lama (satu sesi aktif per user).
  update public.phone_verifications
     set status = 'expired'
   where uid = v_uid and status = 'pending';

  v_token := encode(extensions.gen_random_bytes(16), 'hex');

  insert into public.phone_verifications(uid, phone, token, status, expires_at)
  values (v_uid, v_phone, v_token, 'pending', v_expires);

  return jsonb_build_object(
    'token', v_token,
    'phone', v_phone,
    'expires_at', v_expires
  );
end;
$function$

-- snapshot-fn: phone_verify_status
CREATE OR REPLACE FUNCTION public.phone_verify_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_verified timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select phone, phone_verified_at into v_phone, v_verified
  from public.profiles where id = v_uid;
  return jsonb_build_object(
    'phone', coalesce(v_phone, ''),
    'verified', v_verified is not null,
    'verified_at', v_verified
  );
end;
$function$

-- snapshot-fn: pin_private_chat
CREATE OR REPLACE FUNCTION public.pin_private_chat(p_chat_id text, p_pin boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  me_text text := me::text;
  r record;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select * into r from public.private_chats where chat_id = p_chat_id;
  if not found then raise exception 'Chat not found'; end if;
  if not (me_text = any(r.pinned_by) or me_text = any(r.participants::text[]) or me::text = any(r.participants::text[])) then
    -- also allow if participants is text[] or uuid[]
    null;
  end if;
  -- check participant via text cast
  if not exists (select 1 from unnest(r.participants::text[]) as p where p = me_text) then
    raise exception 'Forbidden';
  end if;

  if p_pin then
    update public.private_chats
    set pinned_by = array(select distinct unnest(array_append(coalesce(pinned_by,'{}'), me_text))),
        pinned_at = coalesce(pinned_at,'{}'::jsonb) || jsonb_build_object(me_text, now()::text)
    where chat_id = p_chat_id;
  else
    update public.private_chats
    set pinned_by = array_remove(coalesce(pinned_by,'{}'), me_text),
        pinned_at = coalesce(pinned_at,'{}'::jsonb) - me_text
    where chat_id = p_chat_id;
  end if;
  return jsonb_build_object('ok', true, 'pinned', p_pin);
end; $function$

-- snapshot-fn: ping_typing
CREATE OR REPLACE FUNCTION public.ping_typing(p_chat_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.chat_ai_pause (chat_id, typing_at, updated_at)
  values (p_chat_id, now(), now())
  on conflict (chat_id) do update
    set typing_at = now(), updated_at = now();
end;
$function$

-- snapshot-fn: points_leaderboard
CREATE OR REPLACE FUNCTION public.points_leaderboard(scope text DEFAULT 'weekly'::text, row_limit integer DEFAULT 50, row_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  me jsonb;
  lim int;
  off int;
  v_me uuid := auth.uid();
begin
  lim := least(greatest(coalesce(row_limit, 50), 1), 100);
  off := greatest(coalesce(row_offset, 0), 0);

  if scope = 'alltime' then
    with ranked as (
      select
        p.id, p.nickname,
        case when public.privacy_can_view(p.id, 'profile_photo', v_me)
             then p.avatar else '' end as avatar,
        p.country, p.points as score, p.is_registered,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank > off and rank <= off + lim;

    with ranked as (
      select p.id, p.points as score,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = v_me;
  else
    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select
        p.id, p.nickname,
        case when public.privacy_can_view(p.id, 'profile_photo', v_me)
             then p.avatar else '' end as avatar,
        p.country, en.score, p.is_registered,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank > off and rank <= off + lim;

    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select p.id, en.score,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = v_me;
  end if;

  return jsonb_build_object(
    'scope', case when scope = 'alltime' then 'alltime' else 'weekly' end,
    'entries', coalesce(result, '[]'::jsonb),
    'me', coalesce(me, 'null'::jsonb)
  );
end;
$function$

-- snapshot-fn: points_quests
CREATE OR REPLACE FUNCTION public.points_quests(tz_offset_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p record;
  wallet_total int;
begin
  select points, room_reads_today, new_chats_today, one_time_actions,
         last_login_date, login_streak
    into p
    from profiles where id = auth.uid();

  select coalesce(sum(amount), 0) into wallet_total
    from coin_ledger where user_id = auth.uid();

  return jsonb_build_object(
    'points', wallet_total,
    'streak', coalesce(p.login_streak, 0),
    'daily', '[]'::jsonb,
    'weekly', '[]'::jsonb,
    'oneTime', '[]'::jsonb
  );
end; $function$

-- snapshot-fn: post_comment_count_sync
CREATE OR REPLACE FUNCTION public.post_comment_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    update public.posts set comment_count = comment_count + 1 where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
    return old;
  end if;
  return null;
end; $function$

-- snapshot-fn: post_like_count_sync
CREATE OR REPLACE FUNCTION public.post_like_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    update public.posts set like_count = like_count + 1 where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
    return old;
  end if;
  return null;
end; $function$

-- snapshot-fn: posts_fill_country
CREATE OR REPLACE FUNCTION public.posts_fill_country()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(new.country,'') = '' then
    select coalesce(country,'') into new.country from public.profiles where id = new.author_id;
  end if;
  return new;
end; $function$

-- snapshot-fn: presence_for
CREATE OR REPLACE FUNCTION public.presence_for(p_uids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  invisible_uid uuid;
  arr jsonb;
begin
  -- Invisible (mis. admin mode) → hilangkan dari hasil, konsisten dgn
  -- get_online_users yang memfilter invisible lewat status.
  select s.invisible_admin_uid into invisible_uid
    from public.app_settings s where s.id = 'global';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',        p.id,
    'nickname',  p.nickname,
    'gender',    p.gender,
    'age',       p.age,
    'country',   p.country,
    'city',      p.city,
    'is_registered', p.is_registered,
    'avatar',    case when public.privacy_can_view(p.id, 'profile_photo', me)
                      then p.avatar else '' end,
    'status',    case when public.privacy_can_view(p.id, 'presence', me)
                      then p.status else 'offline' end,
    'last_seen', case when public.privacy_can_view(p.id, 'last_seen', me)
                      then p.last_seen else null end,
    'about',     case when public.privacy_can_view(p.id, 'about', me)
                      then p.about else '' end
  )), '[]'::jsonb) into arr
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]))
    and p.id <> coalesce(me, '00000000-0000-0000-0000-000000000000'::uuid)
    and (invisible_uid is null or p.id <> invisible_uid)
    -- Hormati blokir dua arah (sama seperti get_online_users).
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    );

  return arr;
end;
$function$

-- snapshot-fn: presence_idle_tick
CREATE OR REPLACE FUNCTION public.presence_idle_tick(p_idle_after interval DEFAULT '00:04:00'::interval)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_n int := 0;
begin
  -- Hanya 'online' (bukan idle/offline/invisible). last_seen masih segar
  -- (< p_idle_after) dikecualikan — mereka benar-benar aktif. Batas atas
  -- 30 mnt = jendela tampil daftar online, supaya tidak menyentuh user yang
  -- sudah "offline efektif" di client.
  -- Dummy dikecualikan: presence-nya diatur ai_presence_tick / admin panel.
  update public.profiles p
     set status = 'idle'
   where p.status = 'online'
     and p.last_seen is not null
     and p.last_seen < now() - p_idle_after
     and p.last_seen >= now() - interval '30 minutes'
     and not exists (
       select 1 from public.dummy_accounts d where d.uid = p.id
     );
  get diagnostics v_n = row_count;
  return v_n;
exception when others then
  return 0;
end;
$function$

-- snapshot-fn: presence_stale_offline
CREATE OR REPLACE FUNCTION public.presence_stale_offline(p_stale_minutes integer DEFAULT 30)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_n int := 0;
begin
  update public.profiles p
     set status = 'offline'
   where p.status in ('online', 'idle')
     and (p.last_seen is null
          or p.last_seen < now() - make_interval(mins => greatest(p_stale_minutes, 1)));
  get diagnostics v_n = row_count;
  return v_n;
exception when others then
  return 0;
end;
$function$

-- snapshot-fn: privacy_can_view
CREATE OR REPLACE FUNCTION public.privacy_can_view(p_owner uuid, p_field text, p_viewer uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vis text;
  v_friend boolean;
  v_excluded boolean;
begin
  if p_owner is null or p_viewer is null then return false; end if;
  if p_owner = p_viewer then return true; end if;

  if coalesce((select privacy_bypass_enabled from public.app_settings where id = 'global'), false)
     and coalesce(auth.email(), '') = 'zunixe@gmail.com' then
    return true;
  end if;

  -- Foto profil: mitra chat private boleh saling lihat. Hanya profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1 from public.private_chats c
    where c.participants @> array[p_owner, p_viewer]::uuid[]
  ) then
    return true;
  end if;

  -- Foto profil: anggota GRUP/room sama boleh saling lihat. Hanya profile_photo.
  if p_field = 'profile_photo' and exists (
    select 1
      from public.room_members a
      join public.room_members b on b.room_id = a.room_id
     where a.user_id = p_owner and b.user_id = p_viewer
  ) then
    return true;
  end if;

  select case p_field
    when 'presence' then presence_visibility
    when 'last_seen' then last_seen_visibility
    when 'profile_photo' then profile_photo_visibility
    when 'about' then about_visibility
    when 'story' then story_visibility
    when 'leaderboard' then leaderboard_visibility
    when 'call' then call_visibility
    else 'nobody'
  end into v_vis
  from public.profiles where id = p_owner;

  v_vis := coalesce(v_vis, 'nobody');
  if v_vis = 'everyone' then return true; end if;
  if v_vis = 'nobody' then return false; end if;

  v_excluded := exists (
    select 1 from public.profile_privacy_exclusions e
    where e.owner_id = p_owner
      and e.excluded_uid = p_viewer
      and e.field = p_field
  );

  if v_vis = 'everyone_except' then
    return not v_excluded;
  end if;

  if v_vis = 'only' then
    return v_excluded;
  end if;

  v_friend := public._privacy_are_friends(p_viewer, p_owner);
  if not v_friend then return false; end if;

  if v_vis = 'friends_except' then
    return not v_excluded;
  end if;

  return true; -- 'friends'
end; $function$

-- snapshot-fn: privacy_excludable_users
CREATE OR REPLACE FUNCTION public.privacy_excludable_users()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'uid', x.id,
        'nickname', x.nickname,
        'avatar', x.avatar,
        'is_registered', x.is_registered,
        'is_friend', x.is_friend
      )
      order by x.is_friend desc, x.nickname
    ),
    '[]'::jsonb
  )
  from (
    select
      p.id,
      p.nickname,
      p.avatar,
      p.is_registered,
      public._privacy_are_friends(auth.uid(), p.id) as is_friend
    from public.profiles p
    where p.id <> auth.uid()
      and (
        -- teman (mutual follow)
        public._privacy_are_friends(auth.uid(), p.id)
        -- orang yang follow saya
        or exists (
          select 1 from public.follows f
          where f.follower_id = p.id and f.followee_id = auth.uid()
        )
        -- subscriber aktif saya
        or exists (
          select 1 from public.subscriptions s
          where s.subscriber_id = p.id and s.creator_id = auth.uid()
            and s.expires_at > now()
        )
        -- pernah 1:1 chat dengan saya (registered MAUPUN anon)
        or exists (
          select 1 from public.private_chats c
          where auth.uid() = any(c.participants)
            and p.id = any(c.participants)
        )
        -- sudah ada di daftar "hanya orang tertentu" saya (field apa pun)
        or exists (
          select 1 from public.profile_privacy_exclusions e
          where e.owner_id = auth.uid() and e.excluded_uid = p.id
        )
      )
    limit 500
  ) x;
$function$

-- snapshot-fn: privacy_friends
CREATE OR REPLACE FUNCTION public.privacy_friends()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'uid', p.id,
        'nickname', p.nickname,
        'avatar', p.avatar,
        'gender', p.gender,
        'is_registered', p.is_registered
      )
      order by p.nickname
    ),
    '[]'::jsonb
  )
  from public.profiles p
  where p.id <> auth.uid()
    and public._privacy_are_friends(auth.uid(), p.id);
$function$

-- snapshot-fn: profile_public
CREATE OR REPLACE FUNCTION public.profile_public(p_user uuid DEFAULT auth.uid())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.profiles%rowtype;
  me uuid := auth.uid();
  v_is_me boolean := (p_user = me);
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;
  return jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case when public.privacy_can_view(r.id, 'presence', me) then r.status else 'offline' end,
    'avatar', case when public.privacy_can_view(r.id, 'profile_photo', me) then r.avatar else '' end,
    'is_registered', r.is_registered,
    'needs_onboarding', coalesce(r.needs_onboarding, false),
    'login_at', r.login_at,
    'created_at', r.created_at,
    'last_seen', case when public.privacy_can_view(r.id, 'last_seen', me) then r.last_seen else null end,
    'about', case when public.privacy_can_view(r.id, 'about', me) then r.about else '' end,
    'hashtags', r.hashtags,
    'points', case when r.id = me then r.points else 0 end,
    'share_location', case when r.id = me then r.share_location else false end,
    'followers_count', r.followers_count,
    'following_count', r.following_count,
    'subscriber_count', r.subscriber_count,
    'subscription_price', r.subscription_price,
    'friends_count', r.friends_count,
    -- Hanya untuk diri sendiri (data sensitif).
    'phone', case when v_is_me then coalesce(r.phone, '') else '' end,
    'birth_date', case when v_is_me then r.birth_date else null end,
    'phone_verified_at', case when v_is_me then r.phone_verified_at else null end
  );
end;
$function$

-- snapshot-fn: profiles_ledger_signup
CREATE OR REPLACE FUNCTION public.profiles_ledger_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.coin_ledger where user_id = NEW.id) then
    insert into public.coin_ledger (user_id, bucket, type, amount, metadata)
    values (NEW.id, 'bonus', 'signup', coalesce(NEW.points, 50),
            jsonb_build_object('reason', 'signup'));
    update public.profiles set points = coalesce(NEW.points, 50) where id = NEW.id;
  end if;
  return NEW;
end; $function$

-- snapshot-fn: purge_deleted_users_90d
CREATE OR REPLACE FUNCTION public.purge_deleted_users_90d()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_deleted integer;
begin
  delete from public.deleted_users
  where deleted_at < now() - interval '90 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$

-- snapshot-fn: purge_expired_stories
CREATE OR REPLACE FUNCTION public.purge_expired_stories()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  delete from public.stories where expires_at <= now();
  get diagnostics n = row_count;
  return n;
end;
$function$

-- snapshot-fn: purge_fcm_token
CREATE OR REPLACE FUNCTION public.purge_fcm_token(p_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_token is null or p_token = '' then return; end if;
  update public.profiles set fcm_token = '' where fcm_token = p_token;
  delete from public.user_devices where fcm_token = p_token;
end;
$function$

-- snapshot-fn: purge_ghost_users
CREATE OR REPLACE FUNCTION public.purge_ghost_users(p_min_age_hours integer DEFAULT 24, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ids uuid[];
  v_count int := 0;
  v_uid uuid;
  v_result jsonb;
begin
  -- Kandidat: anon tanpa profil, cukup umur, dan TANPA jejak apa pun.
  -- Setiap `not exists` WAJIB (fail-safe: ada jejak → tidak dihapus).
  select coalesce(array_agg(u.id), '{}')
    into v_ids
    from auth.users u
    left join public.profiles p on p.id = u.id
   where u.is_anonymous = true
     and u.email is null
     and p.id is null                       -- tanpa profil = hantu
     and u.created_at is not null
     and u.created_at < now() - make_interval(hours => p_min_age_hours)
     and not exists (select 1 from public.dummy_accounts d where d.uid = u.id)
     -- jejak wajib kosong:
     and not exists (select 1 from public.user_devices d where d.user_id = u.id)
     and not exists (select 1 from public.user_location_history l where l.user_id = u.id)
     and not exists (select 1 from public.user_photos ph where ph.user_id = u.id)
     and not exists (select 1 from public.private_chats c where c.participants @> array[u.id]::uuid[])
     and not exists (select 1 from public.private_messages m where m.sender_id = u.id)
     and not exists (select 1 from public.coin_ledger k where k.user_id = u.id)
     and not exists (select 1 from public.point_events e where e.user_id = u.id)
     and not exists (select 1 from public.blocks b where b.blocker_id = u.id or b.blocked_id = u.id)
     and not exists (select 1 from public.reports r where r.reporter_id = u.id or r.reported_id = u.id)
     and not exists (select 1 from public.contact_messages cm where cm.user_id = u.id);

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'count', coalesce(array_length(v_ids, 1), 0),
      'ids', to_jsonb(v_ids)
    );
  end if;

  -- Hapus satu per satu; satu kegagalan tidak menggagalkan sisanya.
  foreach v_uid in array v_ids loop
    begin
      delete from auth.users where id = v_uid;
      v_count := v_count + 1;
    exception when others then
      null;
    end;
  end loop;

  v_result := jsonb_build_object(
    'dry_run', false,
    'count', v_count,
    'candidates', coalesce(array_length(v_ids, 1), 0)
  );
  return v_result;
end;
$function$

-- snapshot-fn: purge_inactive_accounts
CREATE OR REPLACE FUNCTION public.purge_inactive_accounts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cutoff timestamptz := now() - interval '90 days';
  deleted int := 0;
  r record;
begin
  for r in
    select id from public.profiles
    where last_seen < cutoff
      and last_seen is not null
      and id not in (select id from public.profiles where is_registered = true and points > 10000)
  loop
    begin
      perform public.fn_archive_deleted_user(r.id);
    exception when others then null;
    end;

    -- Chat lawan dipertahankan sebagai penanda (isi pesan dihapus).
    perform public.mark_chats_user_deleted(r.id);

    delete from public.follows where follower_id = r.id or followee_id = r.id;
    delete from public.friend_requests where from_id = r.id or to_id = r.id;
    delete from public.blocks where blocker_id = r.id or blocked_id = r.id;
    delete from public.subscriptions where subscriber_id = r.id or creator_id = r.id;
    delete from public.room_messages where sender_id = r.id;
    delete from public.private_messages where sender_id = r.id;
    delete from public.room_presence where user_id = r.id;
    delete from public.profiles where id = r.id;
    deleted := deleted + 1;
    exit when deleted >= 100;
  end loop;
  return jsonb_build_object('deleted', deleted, 'cutoff', cutoff);
end; $function$

-- snapshot-fn: purge_location_history_90d
CREATE OR REPLACE FUNCTION public.purge_location_history_90d()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_deleted integer;
begin
  delete from public.user_location_history
  where created_at < now() - interval '90 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$

-- snapshot-fn: purge_onboarding_placeholders
CREATE OR REPLACE FUNCTION public.purge_onboarding_placeholders(p_min_age_hours integer DEFAULT 24, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ids uuid[];
  v_count int := 0;
  v_uid uuid;
begin
  -- Kandidat: placeholder trigger yang benar-benar tak pernah dipakai.
  select coalesce(array_agg(p.id), '{}')
    into v_ids
    from public.profiles p
   where p.nickname ~ '^Anon[0-9A-F]+$'           -- (1) pola trigger
     and coalesce(p.needs_onboarding, false) = true  -- (2) belum onboarding
     and coalesce(p.is_registered, false) = false     -- (3) bukan akun email
     and p.last_seen = p.created_at                    -- (4) belum pernah aktif
     and p.created_at < now() - make_interval(hours => p_min_age_hours)  -- (6)
     and not exists (select 1 from public.dummy_accounts d where d.uid = p.id) -- (7)
     -- (5) tanpa jejak berharga apa pun:
     and not exists (select 1 from public.user_devices dv where dv.user_id = p.id)
     and not exists (select 1 from public.user_location_history l where l.user_id = p.id)
     and not exists (select 1 from public.private_messages m where m.sender_id = p.id)
     and not exists (select 1 from public.private_chats c where c.participants @> array[p.id]::uuid[])
     and not exists (select 1 from public.coin_ledger k where k.user_id = p.id)
     and not exists (select 1 from public.point_events e where e.user_id = p.id)
     and not exists (select 1 from public.stories s where s.author_id = p.id)
     and not exists (select 1 from public.posts po where po.author_id = p.id)
     and not exists (select 1 from public.follows f where f.follower_id = p.id or f.followee_id = p.id)
     and not exists (select 1 from public.friend_requests fr where fr.from_id = p.id or fr.to_id = p.id)
     and not exists (select 1 from public.user_photos ph where ph.user_id = p.id)
     and not exists (select 1 from public.blocks b where b.blocker_id = p.id or b.blocked_id = p.id)
     and not exists (select 1 from public.reports r where r.reporter_id = p.id or r.reported_id = p.id)
     and not exists (select 1 from public.contact_messages cm where cm.user_id = p.id);

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'count', coalesce(array_length(v_ids, 1), 0),
      'ids', to_jsonb(v_ids)
    );
  end if;

  -- Hapus satu per satu; satu kegagalan tidak menggagalkan sisanya.
  foreach v_uid in array v_ids loop
    begin
      perform public.fn_archive_deleted_user(v_uid, 'onboarding_placeholder');
      delete from public.room_presence where user_id = v_uid;
      delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
      delete from public.reports where reporter_id = v_uid or reported_id = v_uid;
      delete from public.user_photos where user_id = v_uid;
      delete from public.private_messages pm
        using public.private_chats pc
        where pm.chat_id = pc.chat_id and pc.participants @> array[v_uid]::uuid[];
      delete from public.private_chats pc where pc.participants @> array[v_uid]::uuid[];
      delete from public.private_messages where sender_id = v_uid;
      -- Pesan room: SOFT-delete supaya tampil "Pesan dihapus" (bukan hilang).
      update public.messages set is_deleted = true where sender_id = v_uid;
      -- Device & location WAJIB dihapus SEBELUM profiles (FK SET NULL tapi
      -- kolom NOT NULL → 23503 bila profiles lebih dulu).
      delete from public.user_devices where user_id = v_uid;
      delete from public.user_location_history where user_id = v_uid;
      delete from public.contact_messages where user_id = v_uid;
      delete from public.profiles where id = v_uid;
      -- Ledger koin & point_events: trigger append-only menolak DELETE.
      alter table public.coin_ledger disable trigger coin_ledger_no_delete;
      delete from public.coin_ledger where user_id = v_uid;
      alter table public.coin_ledger enable trigger coin_ledger_no_delete;
      delete from public.point_events where user_id = v_uid;
      delete from auth.users where id = v_uid;
      v_count := v_count + 1;
    exception when others then
      -- Satu user gagal (mis. data aneh) tidak menggagalkan seluruh run.
      -- Pastikan trigger coin_ledger kembali ENABLE walau error di tengah.
      begin
        alter table public.coin_ledger enable trigger coin_ledger_no_delete;
      exception when others then null;
      end;
    end;
  end loop;

  return jsonb_build_object(
    'dry_run', false,
    'count', v_count,
    'candidates', coalesce(array_length(v_ids, 1), 0)
  );
end;
$function$

-- snapshot-fn: recount_social_counts
CREATE OR REPLACE FUNCTION public.recount_social_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tot int;
begin
  update public.profiles p
  set followers_count = coalesce((select count(*) from public.follows f where f.followee_id = p.id), 0);
  get diagnostics tot = row_count;

  update public.profiles p
  set following_count = coalesce((select count(*) from public.follows f where f.follower_id = p.id), 0);

  update public.profiles p
  set friends_count = coalesce((
    select count(*)
    from public.follows a
    join public.follows b
      on a.follower_id = b.followee_id
     and a.followee_id = b.follower_id
    where a.follower_id = p.id
  ), 0);

  return jsonb_build_object('ok', true, 'profiles_recounted', tot);
end; $function$

-- snapshot-fn: refund_chat_point
CREATE OR REPLACE FUNCTION public.refund_chat_point(msg_type text)
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
$function$

-- snapshot-fn: register_bonus
CREATE OR REPLACE FUNCTION public.register_bonus()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: reject_join_request
CREATE OR REPLACE FUNCTION public.reject_join_request(p_room_id text, p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare actor_role text;
begin
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role not in ('owner','admin') then raise exception 'Forbidden'; end if;
  update public.room_join_requests
     set status='rejected', decided_at=now(), decided_by=auth.uid()
   where room_id = p_room_id and user_id = p_uid;
end;
$function$

-- snapshot-fn: replace_privacy_exclusions
CREATE OR REPLACE FUNCTION public.replace_privacy_exclusions(p_field text, p_uids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_field not in ('presence','last_seen','profile_photo','about','story','leaderboard','call') then
    raise exception 'Invalid privacy field';
  end if;
  delete from profile_privacy_exclusions where owner_id = auth.uid() and field = p_field;
  insert into profile_privacy_exclusions(owner_id, excluded_uid, field)
  select auth.uid(), x, p_field from unnest(coalesce(p_uids, '{}'::uuid[])) x
  where x <> auth.uid()
  on conflict do nothing;
  return public.my_privacy_settings();
end;
$function$

-- snapshot-fn: reply_post_comment
CREATE OR REPLACE FUNCTION public.reply_post_comment(p_post_id uuid, p_parent_id bigint, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); my_name text; new_id bigint;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) = 0 or length(p_text) > 500 then
    raise exception 'Invalid comment';
  end if;
  if not exists (select 1 from public.post_comments
                  where id = p_parent_id and post_id = p_post_id) then
    raise exception 'Parent not found';
  end if;
  select nickname into my_name from public.profiles where id = me;
  insert into public.post_comments (post_id, author_id, author_name, text, parent_id)
    values (p_post_id, me, coalesce(my_name,'Anon'), p_text, p_parent_id)
    returning id into new_id;
  return jsonb_build_object('ok', true, 'id', new_id);
end; $function$

-- snapshot-fn: request_withdrawal
CREATE OR REPLACE FUNCTION public.request_withdrawal(p_coin_amount integer, p_pay_method text, p_pay_account text, p_pay_holder text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  points_on boolean; rate int; min_coins int;
  min_age_h int; max_day int; min_interval_h int;
  earned int; payout int; acct_age_h int; last_req timestamptz;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled, withdraw_rate_idr, withdraw_min_coins,
         withdraw_min_account_age_hours, withdraw_max_per_day, withdraw_min_interval_hours
    into points_on, rate, min_coins, min_age_h, max_day, min_interval_h
    from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then raise exception 'Points system disabled'; end if;

  -- KYC wajib sudah disetujui
  if not exists (select 1 from kyc_requests k
                 where k.user_id = uid and k.status = 'approved') then
    raise exception 'KYC required';
  end if;

  -- Anti-fraud: umur akun minimal
  select floor(extract(epoch from (now() - p.created_at)) / 3600)::int
    into acct_age_h from profiles p where p.id = uid;
  if acct_age_h < min_age_h then raise exception 'Account too new'; end if;

  -- Anti-fraud: batas harian
  if (select count(*) from withdrawal_requests
      where user_id = uid and created_at >= date_trunc('day', now())) >= max_day then
    raise exception 'Daily limit reached';
  end if;

  -- Anti-fraud: jeda minimum antar request
  select max(created_at) into last_req from withdrawal_requests where user_id = uid;
  if last_req is not null
     and last_req > now() - make_interval(hours => min_interval_h) then
    raise exception 'Too frequent';
  end if;

  if p_coin_amount is null or p_coin_amount < min_coins then
    raise exception 'Below minimum'; end if;
  if length(trim(p_pay_account)) < 5 or length(trim(p_pay_holder)) < 3 then
    raise exception 'Invalid payout info'; end if;

  -- hanya earned yang bisa dicairkan
  select coalesce(sum(amount) filter (where bucket='earned'),0)
    into earned from coin_ledger where user_id = uid;
  if earned < p_coin_amount then raise exception 'Not enough withdrawable'; end if;

  payout := p_coin_amount * rate;

  -- debit earned (hold) — jika ditolak admin, direfund
  insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
    values (uid,'earned','withdraw_request',-p_coin_amount,
            p_pay_method, jsonb_build_object('payout_idr',payout));
  perform public.wallet_sync_points(uid);

  insert into withdrawal_requests (user_id, coin_amount, payout_idr, rate, status,
                                   pay_method, pay_account, pay_holder)
  values (uid, p_coin_amount, payout, rate, 'pending',
          p_pay_method, trim(p_pay_account), trim(p_pay_holder));

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'withdraw_request', -p_coin_amount,
            jsonb_build_object('payout_idr',payout));

  return jsonb_build_object('ok', true, 'coin_amount', p_coin_amount,
    'payout_idr', payout, 'status', 'pending', 'rate', rate);
end; $function$

-- snapshot-fn: reset_phone_verified_on_change
CREATE OR REPLACE FUNCTION public.reset_phone_verified_on_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Nomor diganti (beda digit ternormalisasi) → badge dicabut sampai
  -- verifikasi ulang. Perbandingan pakai digit saja supaya '+62 812' dan
  -- '+62812' dianggap sama.
  if regexp_replace(coalesce(new.phone,''), '[^0-9]', '', 'g')
     is distinct from
     regexp_replace(coalesce(old.phone,''), '[^0-9]', '', 'g')
  then
    new.phone_verified_at := null;
  end if;
  return new;
end;
$function$

-- snapshot-fn: reset_room_password
CREATE OR REPLACE FUNCTION public.reset_room_password(p_room_id text, p_new_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  role text; has_pw boolean;
begin
  role := public.fn_room_role(auth.uid(), p_room_id);
  if role is distinct from 'owner' then
    raise exception 'Only owner can reset password';
  end if;
  if p_new_password is null or btrim(p_new_password) = '' then
    -- hapus password
    update public.rooms set password_hash = null, has_password = false where id = p_room_id;
    return jsonb_build_object('ok', true, 'has_password', false);
  else
    if length(p_new_password) < 4 or length(p_new_password) > 30 then
      raise exception 'Password 4-30 karakter';
    end if;
    update public.rooms set password_hash = crypt(p_new_password, gen_salt('bf')), has_password = true where id = p_room_id;
    return jsonb_build_object('ok', true, 'has_password', true);
  end if;
end;
$function$

-- snapshot-fn: respond_friend_request
CREATE OR REPLACE FUNCTION public.respond_friend_request(p_request_id bigint, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); req record; friend_count int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Guard sosial anon (bypass: dummy & admin) — sebelum apa pun.
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  select * into req from friend_requests where id = p_request_id and to_id = me;
  if not found then raise exception 'Request not found'; end if;
  if req.status <> 'pending' then raise exception 'Already responded'; end if;

  update friend_requests set status = case when p_accept then 'accepted' else 'rejected' end,
    responded_at = now() where id = p_request_id;

  if p_accept then
    insert into follows (follower_id, followee_id) values (req.from_id, req.to_id)
      on conflict do nothing;
    insert into follows (follower_id, followee_id) values (req.to_id, req.from_id)
      on conflict do nothing;

    -- Bonus first-friend untuk KEDUA belah pihak (sekali seumur hidup).
    select friends_count into friend_count from public.profiles where id = req.from_id;
    if coalesce(friend_count, 0) <= 1 then
      perform public.one_time_bonus('first_friend', 0);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'accepted', p_accept);
end;
$function$

-- snapshot-fn: revoke_broadcast
CREATE OR REPLACE FUNCTION public.revoke_broadcast(p_room_id text, p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE actor_role text;
BEGIN
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  IF actor_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'Forbidden'; END IF;
  UPDATE public.room_members SET broadcast_granted = false WHERE room_id = p_room_id AND user_id = p_uid;
  UPDATE public.rooms SET live_uid = NULL, live_started_at = NULL WHERE id = p_room_id AND live_uid = p_uid;
END;
$function$

-- snapshot-fn: reward_photo_slot
CREATE OR REPLACE FUNCTION public.reward_photo_slot(p_slot_index integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: rls_auto_enable
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$

-- snapshot-fn: room_online_counts
CREATE OR REPLACE FUNCTION public.room_online_counts(p_country text)
 RETURNS TABLE(room_id text, count bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT rp.room_id, COUNT(*)::bigint
    FROM public.room_presence rp
      JOIN public.rooms r ON r.id = rp.room_id
        WHERE r.country = p_country
          GROUP BY rp.room_id;
          $function$

-- snapshot-fn: room_pricing
CREATE OR REPLACE FUNCTION public.room_pricing()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return (select jsonb_build_object(
    'create_paid', room_create_paid,
    'create_pw_paid', room_create_pw_paid,
    'join_paid', room_join_paid,
    'extend_paid', room_extend_paid,
    'multiplier', bonus_price_multiplier
  ) from app_settings where id = 'global');
end; $function$

-- snapshot-fn: room_read_bonus
CREATE OR REPLACE FUNCTION public.room_read_bonus()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tot int;
begin
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: room_voice_heartbeat
CREATE OR REPLACE FUNCTION public.room_voice_heartbeat(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return; end if;
  update public.room_voice_speakers
     set updated_at = now()
   where room_id = p_room_id and uid = auth.uid();
end;
$function$

-- snapshot-fn: room_voice_join
CREATE OR REPLACE FUNCTION public.room_voice_join(p_room_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_count int;
  v_allowed boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select (
    exists (select 1 from public.rooms r
             where r.id = p_room_id
               and coalesce(r.is_private, false) = false)
    or exists (select 1 from public.room_members m
                where m.room_id = p_room_id and m.user_id = me)
  ) into v_allowed;
  if not coalesce(v_allowed, false) then
    raise exception 'Not a member';
  end if;

  select count(*) into v_count
    from public.room_voice_speakers s
   where s.room_id = p_room_id
     and s.updated_at > now() - interval '45 seconds'
     and s.uid <> me;
  if v_count >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'stage_full');
  end if;

  insert into public.room_voice_speakers (room_id, uid, updated_at)
  values (p_room_id, me, now())
  on conflict (room_id, uid)
  do update set updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'speakers', coalesce((
      select jsonb_agg(s.uid order by s.updated_at)
        from public.room_voice_speakers s
       where s.room_id = p_room_id
         and s.updated_at > now() - interval '45 seconds'
    ), '[]'::jsonb)
  );
end;
$function$

-- snapshot-fn: room_voice_leave
CREATE OR REPLACE FUNCTION public.room_voice_leave(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return; end if;
  delete from public.room_voice_speakers
   where room_id = p_room_id and uid = auth.uid();
end;
$function$

-- snapshot-fn: room_voice_mute
CREATE OR REPLACE FUNCTION public.room_voice_mute(p_room_id text, p_target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_can boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_target is null or p_target = me then
    return jsonb_build_object('ok', false, 'reason', 'bad_target');
  end if;

  select (
    exists (select 1 from public.rooms r
             where r.id = p_room_id and r.owner_id = me)
    or coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
    or auth.role() = 'service_role'
  ) into v_can;
  if not coalesce(v_can, false) then
    raise exception 'Unauthorized';
  end if;

  delete from public.room_voice_speakers
   where room_id = p_room_id and uid = p_target;

  insert into public.room_voice_signals (room_id, from_uid, to_uid, type, payload)
  values (p_room_id, me, p_target, 'v_mute',
          jsonb_build_object('at', now()));

  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: room_voice_sweep
CREATE OR REPLACE FUNCTION public.room_voice_sweep()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_n int := 0;
  v_m int;
begin
  delete from public.room_voice_speakers
   where updated_at < now() - interval '45 seconds';
  get diagnostics v_n = row_count;

  delete from public.room_voice_signals
   where created_at < now() - interval '2 hours';
  get diagnostics v_m = row_count;

  return v_n + v_m;
end;
$function$

-- snapshot-fn: scrub_reply_snapshot_private
CREATE OR REPLACE FUNCTION public.scrub_reply_snapshot_private()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.is_deleted = true and (old.is_deleted is distinct from true) then
    update public.private_messages pm
    set replied_to_text = null,
        replied_to_sender_name = null
    where pm.replied_to_id = new.id::text;
  end if;
  return new;
end; $function$

-- snapshot-fn: scrub_reply_snapshot_room
CREATE OR REPLACE FUNCTION public.scrub_reply_snapshot_room()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.is_deleted = true and (old.is_deleted is distinct from true) then
    update public.messages m
    set replied_to_text = null,
        replied_to_sender_name = null
    where m.replied_to_id = new.id;
  end if;
  return new;
end; $function$

-- snapshot-fn: sec_to_gc
CREATE OR REPLACE FUNCTION public.sec_to_gc(double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
RETURN CASE WHEN ($1 < '0'::double precision) THEN '0'::double precision WHEN (($1 / ('2'::double precision * earth())) > '1'::double precision) THEN (pi() * earth()) ELSE (('2'::double precision * earth()) * asin(($1 / ('2'::double precision * earth())))) END

-- snapshot-fn: seed_rooms
CREATE OR REPLACE FUNCTION public.seed_rooms(p_country text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_country is null or p_country = '' then
    return;
  end if;

  insert into public.rooms (id, name, description, icon, country, category, "order")
  values
    (p_country || '_general',    'General',    'Chat umum',         '💬', p_country, 'general',    1),
    (p_country || '_curhat',     'Curhat',     'Cerita & curhat',   '💭', p_country, 'curhat',     2),
    (p_country || '_pertemanan', 'Pertemanan', 'Cari teman baru',   '🤝', p_country, 'pertemanan', 3),
    (p_country || '_teknologi',  'Teknologi',  'Diskusi tech',      '💻', p_country, 'teknologi',  4),
    (p_country || '_gaming',     'Gaming',     'Main & bahas game', '🎮', p_country, 'gaming',     5),
    (p_country || '_musik',      'Musik',      'Sharing musik',     '🎵', p_country, 'musik',      6),
    (p_country || '_film',       'Film & TV',  'Review film',       '🎬', p_country, 'film',       7),
    (p_country || '_joke',       'Joke & Meme','Bikin ngakak',      '😂', p_country, 'joke',       8),
    (p_country || '_belajar',    'Belajar',    'Diskusi belajar',   '📚', p_country, 'belajar',    9),
    (p_country || '_flirt',      'Flirt',      'Ngobrol asyik',     '💘', p_country, 'flirt',      10)
  on conflict (id) do nothing;
end;
$function$

-- snapshot-fn: send_coins
CREATE OR REPLACE FUNCTION public.send_coins(p_chat_id text, p_receiver_id uuid, p_amount integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
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

  -- Penerima selalu dapat 'earned' (bisa dicairkan setelah KYC).
  perform public.ledger_credit(p_receiver_id, 'earned', 'coin_received', p_amount,
    p_chat_id, jsonb_build_object('from', uid));

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', p_amount);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0));
end; $function$

-- snapshot-fn: send_friend_request
CREATE OR REPLACE FUNCTION public.send_friend_request(p_to uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); nm text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_to is null or p_to = me then raise exception 'Invalid target'; end if;
  if not exists (select 1 from profiles where id = p_to) then
    raise exception 'User not found';
  end if;
  -- Guard sosial anon (bypass: dummy & admin).
  if not public._anon_write_ok() then
    raise exception 'ANON_DISABLED';
  end if;
  if exists (select 1 from profiles where id = me and is_registered = false)
     or exists (select 1 from profiles where id = p_to and is_registered = false) then
    raise exception 'SOCIAL_REGISTERED_ONLY';
  end if;
  if exists (select 1 from follows where follower_id = me and followee_id = p_to
             and exists (select 1 from follows where follower_id = p_to and followee_id = me)) then
    return jsonb_build_object('ok', true, 'already_friends', true);
  end if;

  insert into friend_requests (from_id, to_id) values (me, p_to)
    on conflict do nothing;

  select nickname into nm from profiles where id = me;
  perform public.social_push(p_to, coalesce(nm, 'Anon'), 'sent you a friend request',
    jsonb_build_object('type', 'friend_request', 'fromUid', me, 'fromName', coalesce(nm, 'Anon')));

  return jsonb_build_object('ok', true, 'status', 'pending');
end;
$function$

-- snapshot-fn: send_gift
CREATE OR REPLACE FUNCTION public.send_gift(p_chat_id text, p_receiver_id uuid, p_gift_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int; mult int;
  my_name text; my_gender text; am_registered boolean;
  n int; bonus_price int; cut int; net int;
  tier text; remaining int; recv_bucket text; recv_amount int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;

  select points_enabled, coalesce(gift_cut_pct,30), coalesce(bonus_price_multiplier,3)
    into points_on, cut_pct, mult from app_settings where id = 'global';
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

  bonus_price := n * mult;
  tier := (public.ledger_spend_dual(uid, 'gift_sent', n, bonus_price, p_chat_id))->>'tier';
  remaining := public.wallet_sync_points(uid);

  if tier = 'paid' then
    cut := (n * cut_pct) / 100;
    net := n - cut;
    recv_bucket := 'earned';
    recv_amount := net;
    if cut > 0 then
      insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
        values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
                jsonb_build_object('gift', p_gift_id, 'gross', n, 'net', net, 'pct', cut_pct));
    end if;
  else
    net := n;
    cut := 0;
    recv_bucket := 'bonus';
    recv_amount := bonus_price;
  end if;

  if recv_amount > 0 then
    perform public.ledger_credit(p_receiver_id, recv_bucket, 'gift_recv', recv_amount,
      p_chat_id, jsonb_build_object('gift', p_gift_id, 'from', uid, 'tier', tier));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -case when tier = 'paid' then n else bonus_price end,
            jsonb_build_object('gift', p_gift_id, 'tier', tier)),
           (p_receiver_id, 'gift_recv', recv_amount,
            jsonb_build_object('gift', p_gift_id, 'tier', tier));

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut, 'tier', tier);
end; $function$

-- snapshot-fn: send_reengage_notifications
CREATE OR REPLACE FUNCTION public.send_reengage_notifications(p_batch integer DEFAULT 400)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  enabled boolean;
  rec record;
  sent int := 0;
  day_no int;
  body_id text;
  body_en text;
begin
  select reengage_enabled into enabled from app_settings where id = 'global';
  if enabled is not true then
    return 0;
  end if;

  for rec in
    select p.id, p.nickname, d.fcm_token,
           case when p.last_seen is null then 1
                else greatest(1, extract(day from (now() - p.last_seen))::int) end as offline_days
    from profiles p
    join user_devices d on d.user_id = p.id
      and d.is_active = true
      and d.fcm_token is not null and d.fcm_token <> ''
    where p.status <> 'online'
      and p.last_seen < now() - interval '1 day'
      and p.last_seen >= now() - interval '8 days'
      and (p.last_reengage_at is null or p.last_reengage_at < now() - interval '20 hours')
    order by p.last_seen desc
    limit least(greatest(coalesce(p_batch, 400), 1), 1000)
  loop
    day_no := ((rec.offline_days - 1) % 3) + 1;
    case day_no
      when 1 then begin
        body_id := '👀 Ada obrolan seru yang nungguin kamu di ChatYuk!';
        body_en := '👀 Fun chats are waiting for you on ChatYuk!';
      end;
      when 2 then begin
        body_id := '🔥 Room-nya rame lagi — yuk gabung di ChatYuk!';
        body_en := '🔥 Rooms are getting busy — join us on ChatYuk!';
      end;
      else begin
        body_id := '💬 Teman-temanmu aktif lagi, yuk buka ChatYuk!';
        body_en := '💬 Your friends are active again — open ChatYuk!';
      end;
    end case;

    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
      body := jsonb_build_object(
        'token', rec.fcm_token,
        'title', 'ChatYuk',
        'body', body_id,
        'data', jsonb_build_object(
          'type', 'reengage'
        )
      )
    );
    sent := sent + 1;

    update profiles set last_reengage_at = now() where id = rec.id;
  end loop;
  return sent;
end; $function$

-- snapshot-fn: send_room_gift
CREATE OR REPLACE FUNCTION public.send_room_gift(p_room_id text, p_gift_id text, p_qty integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  g record; r record; points_on boolean; cut_pct int;
  my_name text; my_gender text;
  b int; t int; e int; need int;
  pay_bonus int := 0; pay_topup int := 0; pay_earned int := 0;
  n int; cut int; net int;
  earn_src int; recv_earned int; recv_bonus int; remaining int;
  host_id uuid;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 20 then
    raise exception 'Invalid qty';
  end if;

  select points_enabled, coalesce(gift_cut_pct,30) into points_on, cut_pct
    from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins * p_qty;

  -- Room harus private (live room), aktif, dan punya owner (host)
  select * into r from rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.is_private is not true then raise exception 'Not a live room'; end if;
  if r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;
  host_id := r.owner_id;
  if host_id is null then raise exception 'Room has no host'; end if;
  if host_id = uid then raise exception 'Cannot gift self'; end if;

  -- Pengirim harus member room atau host-nya sendiri (tidak relevan, tapi aman)
  if not exists (select 1 from room_members rm
      where rm.room_id = p_room_id and rm.user_id = uid)
    and not exists (select 1 from rooms r2
      where r2.id = p_room_id and r2.owner_id = uid) then
    raise exception 'Not a room member';
  end if;

  -- saldo & porsi bucket pengirim
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = uid;
  if (b + t + e) < n then raise exception 'Not enough points'; end if;

  need := n;
  pay_bonus  := least(b, need); need := need - pay_bonus;
  pay_topup  := least(t, need); need := need - pay_topup;
  pay_earned := least(e, need); need := need - pay_earned;

  if pay_bonus > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'bonus','gift_sent',-pay_bonus,p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'room',true));
  end if;
  if pay_topup > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'topup','gift_sent',-pay_topup,p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'room',true));
  end if;
  if pay_earned > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'earned','gift_sent',-pay_earned,p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'room',true));
  end if;
  remaining := public.wallet_sync_points(uid);

  -- platform cut + net ke host (lineage proporsional, pola phase3)
  cut := (n * cut_pct) / 100;
  net := n - cut;

  earn_src := pay_topup + pay_earned;
  if net <= 0 then
    recv_earned := 0; recv_bonus := 0;
  elsif earn_src = 0 then
    recv_earned := 0; recv_bonus := net;
  elsif pay_bonus = 0 then
    recv_earned := net; recv_bonus := 0;
  else
    recv_earned := (net * earn_src) / n;
    recv_bonus  := net - recv_earned;
  end if;

  if recv_earned > 0 then
    perform public.ledger_credit(host_id,'earned','gift_recv',recv_earned,p_room_id,
      jsonb_build_object('gift',p_gift_id,'qty',p_qty,'from',uid));
  end if;
  if recv_bonus > 0 then
    perform public.ledger_credit(host_id,'bonus','gift_recv',recv_bonus,p_room_id,
      jsonb_build_object('gift',p_gift_id,'qty',p_qty,'from',uid));
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, host_id, p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'gross',n,'net',net,'pct',cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n, jsonb_build_object('gift',p_gift_id,'qty',p_qty)),
           (host_id, 'gift_recv', net, jsonb_build_object('gift',p_gift_id,'qty',p_qty));

  -- pesan bukti gift di room feed (realtime ke semua penonton)
  select nickname, gender into my_name, my_gender from public.profiles where id = uid;
  insert into public.messages (room_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_room_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'qty', p_qty, 'gross', n, 'net', net, 'cut', cut);
end; $function$

-- snapshot-fn: set_dummy_hold
CREATE OR REPLACE FUNCTION public.set_dummy_hold(p_uid uuid, p_held boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  update public.dummy_accounts set ai_hold_active = p_held where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$function$

-- snapshot-fn: set_member_role
CREATE OR REPLACE FUNCTION public.set_member_role(p_room_id text, p_uid uuid, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  my_role text;
  target_role text;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_uid is null or p_uid = me then raise exception 'Invalid target'; end if;
  if p_role not in ('admin', 'member') then raise exception 'Invalid role'; end if;
  if not exists (select 1 from public.rooms where id = p_room_id and is_private) then
    raise exception 'Room not found';
  end if;

  my_role := public.fn_room_role(me, p_room_id);
  if my_role not in ('owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  select role into target_role from public.room_members
   where room_id = p_room_id and user_id = p_uid;
  if target_role is null then raise exception 'Not a member'; end if;
  if target_role = 'owner' then raise exception 'Forbidden'; end if;
  -- Demote admin → member hanya owner (selaras kick_room_member).
  if target_role = 'admin' and my_role <> 'owner' then
    raise exception 'Forbidden';
  end if;

  update public.room_members set role = p_role
   where room_id = p_room_id and user_id = p_uid;
  return jsonb_build_object('ok', true, 'role', p_role);
end;
$function$

-- snapshot-fn: set_participant_registered
CREATE OR REPLACE FUNCTION public.set_participant_registered()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record;
begin
  new.participant_registered := '{}'::jsonb;
  for rec in
    select id, is_registered from public.profiles where id = any(new.participants)
  loop
    new.participant_registered := new.participant_registered || jsonb_build_object(rec.id::text, rec.is_registered);
  end loop;
  return new;
end;
$function$

-- snapshot-fn: set_room_presence_from_profile
CREATE OR REPLACE FUNCTION public.set_room_presence_from_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  profile_nickname text;
  profile_gender text;
  profile_registered boolean;
begin
  select nickname, gender, is_registered into profile_nickname, profile_gender, profile_registered
  from public.profiles where id = new.user_id;
  if profile_nickname is not null then
    new.nickname := profile_nickname;
  end if;
  if profile_gender is not null then
    new.gender := profile_gender;
  end if;
  if profile_registered is not null then
    new.is_registered := profile_registered;
  end if;
  return new;
end;
$function$

-- snapshot-fn: set_sender_name_from_profile
CREATE OR REPLACE FUNCTION public.set_sender_name_from_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  profile_nickname text;
  profile_gender text;
  profile_registered boolean;
begin
  select nickname, gender, is_registered into profile_nickname, profile_gender, profile_registered
  from public.profiles where id = new.sender_id;
  if profile_nickname is not null then
    new.sender_name := profile_nickname;
  end if;
  if profile_gender is not null then
    new.sender_gender := profile_gender;
  end if;
  if profile_registered is not null then
    new.is_registered := profile_registered;
  end if;
  return new;
end;
$function$

-- snapshot-fn: set_subscription_price
CREATE OR REPLACE FUNCTION public.set_subscription_price(p_price integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); am_registered boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  select is_registered into am_registered from profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;
  if p_price < 0 or p_price > 100000 then raise exception 'Invalid price'; end if;
  update profiles set subscription_price = p_price where id = me;
  return jsonb_build_object('ok', true, 'price', p_price);
end; $function$

-- snapshot-fn: share_post
CREATE OR REPLACE FUNCTION public.share_post(p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); c int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'Post not found';
  end if;
  insert into public.post_shares (post_id, user_id) values (p_post_id, me)
    on conflict do nothing;
  if found then
    update public.posts set share_count = share_count + 1 where id = p_post_id;
  end if;
  select share_count into c from public.posts where id = p_post_id;
  return jsonb_build_object('ok', true, 'share_count', c);
end; $function$

-- snapshot-fn: share_post_comment
CREATE OR REPLACE FUNCTION public.share_post_comment(p_comment_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); c int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.post_comments where id = p_comment_id) then
    raise exception 'Comment not found';
  end if;
  insert into public.comment_shares (comment_id, user_id) values (p_comment_id, me)
    on conflict do nothing;
  if found then
    update public.post_comments set share_count = share_count + 1 where id = p_comment_id;
  end if;
  select share_count into c from public.post_comments where id = p_comment_id;
  return jsonb_build_object('ok', true, 'share_count', c);
end; $function$

-- snapshot-fn: social_counts_uids
CREATE OR REPLACE FUNCTION public.social_counts_uids(p_uids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object(
    'friends',   coalesce(p.friends_count, 0),
    'followers', coalesce(p.followers_count, 0)
  )), '{}'::jsonb)
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]));
$function$

-- snapshot-fn: social_list
CREATE OR REPLACE FUNCTION public.social_list(p_kind text, p_user uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  res jsonb;
  target uuid := coalesce(p_user, auth.uid());
  v_me uuid := auth.uid();
  lim int := greatest(1, least(p_limit, 200));
  off int := greatest(0, coalesce(p_offset, 0));
begin
  if p_kind = 'followers' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.follower_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, f.created_at
      from follows f join profiles p on p.id = f.follower_id
      where f.followee_id = target
      order by f.created_at desc
      limit lim offset off
    ) x;
  elsif p_kind = 'following' then
    select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res
    from (
      select f.followee_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, f.created_at
      from follows f join profiles p on p.id = f.followee_id
      where f.follower_id = target
      order by f.created_at desc
      limit lim offset off
    ) x;
  elsif p_kind = 'friends' then
    select coalesce(jsonb_agg(x order by x.nickname), '[]'::jsonb) into res
    from (
      select p.id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered
      from follows a join follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join profiles p on p.id = a.followee_id
      where a.follower_id = target and p.id <> target
      order by p.nickname
      limit lim offset off
    ) x;
  elsif p_kind = 'subscribers' then
    select coalesce(jsonb_agg(x order by x.expires_at desc), '[]'::jsonb) into res
    from (
      select s.subscriber_id as uid, p.nickname,
             case when public.privacy_can_view(p.id, 'profile_photo', v_me)
                  then p.avatar else '' end as avatar,
             p.gender, p.is_registered, s.expires_at
      from subscriptions s join profiles p on p.id = s.subscriber_id
      where s.creator_id = target and s.expires_at > now()
      order by s.expires_at desc
      limit lim offset off
    ) x;
  else
    raise exception 'Invalid kind';
  end if;
  return coalesce(res, '[]'::jsonb);
end;
$function$

-- snapshot-fn: social_push
CREATE OR REPLACE FUNCTION public.social_push(p_to uuid, p_title text, p_body text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rec record;
  sent boolean := false;
begin
  -- kirim ke semua device aktif yang punya token
  for rec in
    select fcm_token from public.user_devices
    where user_id = p_to and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object('token', rec.fcm_token, 'title', p_title, 'body', p_body, 'data', (coalesce(p_data, '{}'::jsonb) || jsonb_build_object('toUid', p_to)))
      );
    exception when others then null;
    end;
  end loop;

  -- fallback: jika belum ada baris device dengan token (klien lama), pakai profiles.fcm_token
  if not sent then
    declare t text;
    begin
      select fcm_token into t from public.profiles where id = p_to;
      if t is not null and t <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object('token', t, 'title', p_title, 'body', p_body, 'data', (coalesce(p_data, '{}'::jsonb) || jsonb_build_object('toUid', p_to)))
        );
      end if;
    exception when others then null;
    end;
  end if;
end;
$function$

-- snapshot-fn: spend_yukcoin
CREATE OR REPLACE FUNCTION public.spend_yukcoin(p_user uuid, p_feature text, p_amount integer, p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e int; b int; need int; take int; tier text;
begin
  -- GUARD KEAMANAN (2026-10-22): user hanya boleh mendebit saldo SENDIRI.
  -- service_role (auth.uid() null) tetap bebas untuk job server.
  if auth.uid() is not null and p_user is distinct from auth.uid() then
    raise exception 'Forbidden: tidak boleh mendebit saldo user lain'
      using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = p_user;

  if (e + b) < p_amount then
    raise exception 'YukCoin tidak cukup';
  end if;

  need := p_amount;

  -- earned dulu
  take := least(e, need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (p_user, 'earned', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
    need := need - take;
  end if;

  -- sisanya dari bonus
  if need > 0 then
    take := least(b, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
  end if;

  tier := case when e >= p_amount then 'earned' else 'mixed' end;

  -- Log pemakaian + event analytics.
  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (p_user, p_feature, p_amount, p_ref, coalesce(p_meta, '{}'::jsonb));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, p_feature, -p_amount,
            jsonb_build_object('feature', p_feature, 'ref', p_ref, 'tier', tier));

  return jsonb_build_object(
    'tier', tier,
    'remaining', public.yukcoin_total(p_user)
  );
end; $function$

-- snapshot-fn: start_broadcast
CREATE OR REPLACE FUNCTION public.start_broadcast(p_room_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cnt int; role text;
begin
  role := public.fn_room_role(auth.uid(), p_room_id);
  if role is null then raise exception 'Not a member'; end if;
  select count(*) into cnt from public.room_broadcasters where room_id = p_room_id;
  if cnt >= 4 then raise exception 'Broadcast full (4/4)'; end if;
  insert into public.room_broadcasters(room_id, user_id) values (p_room_id, auth.uid())
    on conflict do nothing;
  -- jaga live_uid untuk kompatibilitas UI lama (set jika kosong)
  update public.rooms set live_uid = auth.uid(), live_started_at = now()
    where id = p_room_id and live_uid is null;
  return jsonb_build_object('ok', true);
end; $function$

-- snapshot-fn: stop_broadcast
CREATE OR REPLACE FUNCTION public.stop_broadcast(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare actor_role text; cur uuid;
begin
  cur := (select live_uid from public.rooms where id = p_room_id);
  if cur is null then return; end if;
  -- Broadcaster sendiri atau owner/admin boleh menghentikan.
  if auth.uid() = cur then
    null;
  elsif public.fn_room_role(auth.uid(), p_room_id) not in ('owner','admin') then
    raise exception 'Forbidden';
  end if;
  update public.rooms set live_uid=null, live_started_at=null where id = p_room_id;
end;
$function$

-- snapshot-fn: stop_broadcast_v2
CREATE OR REPLACE FUNCTION public.stop_broadcast_v2(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.room_broadcasters where room_id = p_room_id and user_id = auth.uid();
  -- jika yang stop adalah pemilik live_uid, kosongkan live_uid
  update public.rooms set live_uid = null, live_started_at = null
    where id = p_room_id and live_uid = auth.uid();
  -- jika masih ada broadcaster lain, promosikan satu jadi live_uid
  update public.rooms set live_uid = (
    select user_id from public.room_broadcasters where room_id = p_room_id order by started_at limit 1
  ), live_started_at = now()
  where id = p_room_id and live_uid is null
    and exists (select 1 from public.room_broadcasters where room_id = p_room_id);
end; $function$

-- snapshot-fn: storage_object_owner_ok
CREATE OR REPLACE FUNCTION public.storage_object_owner_ok(p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'storage'
AS $function$
declare
  v_uid     text := auth.uid()::text;
  v_parts   text[] := storage.foldername(p_name);
  v_prefix  text := coalesce(v_parts[1], '');
  v_seg     text := coalesce(v_parts[2], '');
  v_base    text;
  v_stem    text;
  v_room    text;
begin
  if public.is_admin_request() then
    return true;
  end if;

  if coalesce(v_uid, '') = '' then
    return false;
  end if;

  v_base := coalesce(nullif(split_part(p_name, '/',
              array_length(string_to_array(p_name, '/'), 1)), ''), '');
  v_stem := split_part(v_base, '.', 1);

  -- avatars/<uid>_<ts>.jpg atau avatars/<uid>.jpg
  if v_prefix = 'avatars' then
    return (
      v_stem = v_uid
      or v_stem like v_uid || '\_%'
    );
  end if;

  -- gallery|posts|story|timeline/<uid>/<file>
  if v_prefix in ('gallery', 'posts', 'story', 'timeline') then
    return v_seg = v_uid;
  end if;

  -- room-icons/<uid>/<file>
  if v_prefix = 'room-icons' then
    return v_seg = v_uid;
  end if;

  -- stickers/<uid>/<file>  (stiker; owner-only)
  if v_prefix = 'stickers' then
    return v_seg = v_uid;
  end if;

  -- chat|voice/<chatId>/<file>
  if v_prefix in ('chat', 'voice') then
    -- (a) chat private → peserta.
    if exists (
      select 1 from public.private_chats pc
      where pc.chat_id = v_seg
        and auth.uid() = any (pc.participants)
    ) then
      return true;
    end if;
    -- (b) ROOM: segmen 'room_<roomId>' (foto/voice yang diunggah ke room).
    if v_seg like 'room\_%' then
      v_room := substr(v_seg, 6);   -- buang 'room_'
      -- Global room (publik) → siapa pun (terautentikasi) boleh posting.
      if exists (
        select 1 from public.rooms r
        where r.id = v_room and r.is_private = false
      ) then
        return true;
      end if;
      -- Grup private → harus anggota.
      return exists (
        select 1 from public.room_members m
        where m.room_id = v_room and m.user_id = auth.uid()
      );
    end if;
    return false;
  end if;

  -- prefix tidak dikenal → tolak (fail-closed)
  return false;
end;
$function$

-- snapshot-fn: story_slides
CREATE OR REPLACE FUNCTION public.story_slides(p_author uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'image_path', s.image_path, 'text_overlay', s.text_overlay,
    'text_x', s.text_x, 'text_y', s.text_y, 'text_color', s.text_color,
    'text_size', s.text_size, 'text_scale', s.text_scale,
    'text_rotation', s.text_rotation, 'text_bg', s.text_bg,
    'visibility', s.visibility, 'owner_only', s.owner_only,
    'media_type', s.media_type, 'video_path', s.video_path,
    'duration_ms', s.duration_ms,
    'like_count', (select count(*) from public.story_likes l where l.story_id = s.id),
    'liked', exists (select 1 from public.story_likes l where l.story_id = s.id and l.user_id = auth.uid()),
    'created_at', s.created_at
  ) order by s.created_at asc), '[]'::jsonb) into result
  from public.stories s
  where s.author_id = p_author and s.expires_at > now()
    and public.privacy_can_view(s.author_id, 'story', auth.uid())
    and (
      -- Admin lihat SEMUA (termasuk owner_only) — untuk moderasi.
      public.is_admin_request()
      -- Author lihat miliknya sendiri (termasuk yang owner_only).
      or s.author_id = auth.uid()
      -- Lain: hormati owner_only + visibility + blokir.
      or (
        not s.owner_only
        and ((s.visibility = 'everyone')
          or (s.visibility = 'followers' and exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = s.author_id))
          or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))
        and not exists (select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id) or (b.blocker_id = s.author_id and b.blocked_id = auth.uid()))
      )
    );
  return result;
end;
$function$

-- snapshot-fn: story_tray
CREATE OR REPLACE FUNCTION public.story_tray()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_admin boolean := public.is_admin_request();
begin
  select coalesce(jsonb_agg(t.obj order by t.sort_own desc, t.sort_muted asc, t.sort_unseen desc, t.latest_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'author_id', a.author_id,
        'author_name', a.author_name,
        'avatar', a.avatar,
        'is_registered', a.is_registered,
        'slide_count', a.slide_count,
        'thumb_path', a.thumb_path,
        'has_unseen', a.unseen_count > 0 and not a.muted,
        'own', a.author_id = auth.uid(),
        'muted', a.muted,
        'has_video', a.has_video,
        'has_owner_only', a.has_owner_only,
        'expires_at', a.expires_at
      ) as obj,
      (a.author_id = auth.uid()) as sort_own,
      coalesce(a.muted, false) as sort_muted,
      (a.unseen_count > 0 and not coalesce(a.muted, false)) as sort_unseen,
      a.latest_at
    from (
      select s.author_id,
             max(s.author_name) as author_name,
             case when public.privacy_can_view(s.author_id, 'profile_photo', auth.uid())
                  then (select avatar from public.profiles p where p.id = s.author_id)
                  else '' end as avatar,
             (select is_registered from public.profiles p where p.id = s.author_id) as is_registered,
             count(*) as slide_count,
             (select s2.image_path from public.stories s2
              where s2.author_id = s.author_id and s2.expires_at > now()
              order by s2.created_at desc limit 1) as thumb_path,
             max(s.created_at) as latest_at,
             max(s.expires_at) as expires_at,
             bool_or(s.media_type = 'video') as has_video,
             bool_or(s.owner_only) as has_owner_only,
             exists (
               select 1 from public.story_mutes m
               where m.muter_id = auth.uid() and m.muted_id = s.author_id
             ) as muted,
             count(*) filter (
               where not exists (
                 select 1 from public.story_views v
                 where v.story_id = s.id and v.viewer_id = auth.uid()
               )
             ) as unseen_count
      from public.stories s
      where s.expires_at > now()
        -- Admin lihat semua author (moderasi); user hormati privacy author.
        and (v_admin or public.privacy_can_view(s.author_id, 'story', auth.uid()))
        and (
          v_admin
          or s.author_id = auth.uid()
          or (
            not s.owner_only
            and ((s.visibility = 'everyone')
              or (s.visibility = 'followers' and exists (
                    select 1 from public.follows f
                    where f.follower_id = auth.uid()
                      and f.followee_id = s.author_id))
              or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))
            and not exists (
              select 1 from public.blocks b
              where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
                 or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
            )
          )
        )
      group by s.author_id
    ) a
  ) t;
  return result;
end;
$function$

-- snapshot-fn: story_viewers
CREATE OR REPLACE FUNCTION public.story_viewers(p_story_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  -- Pemilik slide ATAU admin (guard admin anti-rentan: cek email di DB,
  -- bukan hanya klaim JWT — pola is_admin_request()).
  if not exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and (s.author_id = auth.uid() or public.is_admin_request())
  ) then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'viewer_id', v.viewer_id,
    'nickname', pr.nickname,
    'avatar', pr.avatar,
    'viewed_at', v.viewed_at,
    'liked', exists (
      select 1 from public.story_likes l
      where l.story_id = p_story_id and l.user_id = v.viewer_id)
  ) order by v.viewed_at desc), '[]'::jsonb)
  into result
  from public.story_views v
  join public.profiles pr on pr.id = v.viewer_id
  where v.story_id = p_story_id
    -- Ghost-mode: baris admin tidak pernah tampil di daftar penonton,
    -- walau lolos tercatat via client lama/bypass.
    and not exists (
      select 1 from auth.users u
      where u.id = v.viewer_id
        and lower(coalesce(u.email, '')) = 'zunixe@gmail.com'
    );
  return result;
end;
$function$

-- snapshot-fn: streak_bonus_amount
CREATE OR REPLACE FUNCTION public.streak_bonus_amount(streak integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$ select 0; $function$

-- snapshot-fn: submit_kyc
CREATE OR REPLACE FUNCTION public.submit_kyc(p_full_name text, p_id_type text, p_id_number text, p_id_photo text, p_selfie_photo text, p_birth_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if length(trim(p_full_name)) < 3 then raise exception 'Invalid name'; end if;
  if length(trim(p_id_number)) < 8 then raise exception 'Invalid ID number'; end if;
  if length(p_id_photo) < 100 or length(p_selfie_photo) < 100 then
    raise exception 'Photos required'; end if;

  if exists (select 1 from kyc_requests
             where user_id = uid and status in ('pending', 'approved')) then
    raise exception 'KYC already submitted';
  end if;

  insert into kyc_requests (user_id, status, full_name, id_type, id_number,
                            id_photo, selfie_photo, birth_date)
  values (uid, 'pending', p_full_name, coalesce(p_id_type, 'ktp'), p_id_number,
          p_id_photo, p_selfie_photo, p_birth_date);

  return jsonb_build_object('ok', true, 'status', 'pending');
end; $function$

-- snapshot-fn: subscribe_creator
CREATE OR REPLACE FUNCTION public.subscribe_creator(p_creator uuid, p_periods integer DEFAULT 1)
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
end; $function$

-- snapshot-fn: subscriber_count_sync
CREATE OR REPLACE FUNCTION public.subscriber_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    update profiles set subscriber_count = subscriber_count + 1 where id = new.creator_id;
    return new;
  elsif tg_op = 'DELETE' then
    update profiles set subscriber_count = greatest(subscriber_count - 1, 0) where id = old.creator_id;
    return old;
  end if;
  return null;
end; $function$

-- snapshot-fn: sync_dummy_nickname
CREATE OR REPLACE FUNCTION public.sync_dummy_nickname()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.dummy_accounts
     set nickname = new.nickname
   where uid = new.id
     and nickname is distinct from new.nickname;
  return new;
end;
$function$

-- snapshot-fn: sync_private_last_message_on_edit
CREATE OR REPLACE FUNCTION public.sync_private_last_message_on_edit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.text is not distinct from old.text then
    return new;
  end if;
  update public.private_chats pc
     set last_message = case
       when new.type = 'image' then '[Foto]'
       when new.type = 'view_once' then '[Foto]'
       when new.type = 'coin' then '[Koin]'
       when new.type = 'gift' then '[Hadiah]'
       else new.text end
   where pc.chat_id = new.chat_id
     and not exists (
       select 1 from public.private_messages m
        where m.chat_id = new.chat_id
          and (m.created_at, m.id) > (new.created_at, new.id)
     );
  return new;
end;
$function$

-- snapshot-fn: sync_profile_names
CREATE OR REPLACE FUNCTION public.sync_profile_names()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.nickname is distinct from old.nickname then
    update public.posts
       set author_name = new.nickname
     where author_id = new.id
       and author_name is distinct from new.nickname;

    update public.post_comments
       set author_name = new.nickname
     where author_id = new.id
       and author_name is distinct from new.nickname;

    update public.stories
       set author_name = new.nickname
     where author_id = new.id
       and author_name is distinct from new.nickname;

    update public.user_devices
       set nickname_snapshot = new.nickname
     where user_id = new.id
       and nickname_snapshot is distinct from new.nickname;
  end if;
  return new;
end; $function$

-- snapshot-fn: sync_profile_to_chats
CREATE OR REPLACE FUNCTION public.sync_profile_to_chats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin if new.nickname is distinct from old.nickname then update private_chats set participant_names = jsonb_set(participant_names, array[new.id::text], to_jsonb(new.nickname)) where participant_names ? new.id::text; end if; if new.gender is distinct from old.gender then update private_chats set participant_genders = jsonb_set(participant_genders, array[new.id::text], to_jsonb(new.gender)) where participant_genders ? new.id::text; end if; if new.age is distinct from old.age then update private_chats set participant_ages = jsonb_set(participant_ages, array[new.id::text], to_jsonb(new.age)) where participant_ages ? new.id::text; end if; if new.country is distinct from old.country then update private_chats set participant_locations = jsonb_set(participant_locations, array[new.id::text], to_jsonb(new.country)) where participant_locations ? new.id::text; end if; return new; end; $function$

-- snapshot-fn: timeline_pricing
CREATE OR REPLACE FUNCTION public.timeline_pricing()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return (select jsonb_build_object(
    'boost_paid', cost_post_boost,
    'boost_bonus', cost_post_boost * bonus_price_multiplier,
    'multiplier', bonus_price_multiplier,
    'posts_daily_limit', posts_daily_limit
  ) from public.app_settings where id = 'global');
end; $function$

-- snapshot-fn: toggle_comment_like
CREATE OR REPLACE FUNCTION public.toggle_comment_like(p_comment_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  liked boolean;
  v_count int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.post_comments where id = p_comment_id) then
    raise exception 'Comment not found';
  end if;
  if exists (select 1 from public.comment_likes where comment_id = p_comment_id and user_id = me) then
    delete from public.comment_likes where comment_id = p_comment_id and user_id = me;
    liked := false;
  else
    insert into public.comment_likes (comment_id, user_id) values (p_comment_id, me);
    liked := true;
  end if;
  select like_count into v_count from public.post_comments where id = p_comment_id;
  return jsonb_build_object('ok', true, 'liked', liked, 'likeCount', coalesce(v_count, 0));
end; $function$

-- snapshot-fn: toggle_post_like
CREATE OR REPLACE FUNCTION public.toggle_post_like(p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  liked boolean;
  v_count int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'Post not found';
  end if;
  if exists (select 1 from public.post_likes where post_id = p_post_id and user_id = me) then
    delete from public.post_likes where post_id = p_post_id and user_id = me;
    liked := false;
  else
    insert into public.post_likes (post_id, user_id) values (p_post_id, me);
    liked := true;
  end if;
  -- Baca ulang counter yang sudah di-update trigger dalam transaksi yang
  -- sama → nilai konsisten & absolut (tidak bergantung hitung lokal FE).
  select like_count into v_count from public.posts where id = p_post_id;
  return jsonb_build_object('ok', true, 'liked', liked, 'likeCount', coalesce(v_count, 0));
end; $function$

-- snapshot-fn: toggle_story_like
CREATE OR REPLACE FUNCTION public.toggle_story_like(p_story_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_liked boolean;
  v_count int;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  -- Guard: story aktif + boleh dilihat (visibility/blokir), atau milik sendiri.
  if not exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and s.expires_at > now()
      and (
        s.author_id = v_uid
        or (
          (s.visibility = 'everyone')
          or (s.visibility = 'followers' and exists (
                select 1 from public.follows f
                where f.follower_id = v_uid and f.followee_id = s.author_id))
          or (s.visibility = 'friends' and public._are_friends(v_uid, s.author_id))
        )
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = v_uid and b.blocked_id = s.author_id)
             or (b.blocker_id = s.author_id and b.blocked_id = v_uid)
        )
      )
  ) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  delete from public.story_likes
  where story_id = p_story_id and user_id = v_uid;
  if found then
    v_liked := false;
  else
    insert into public.story_likes (story_id, user_id)
    values (p_story_id, v_uid)
    on conflict (story_id, user_id) do nothing;
    v_liked := true;
  end if;

  select count(*) into v_count
  from public.story_likes where story_id = p_story_id;
  return jsonb_build_object('ok', true, 'liked', v_liked, 'count', v_count);
end;
$function$

-- snapshot-fn: touch_broadcast
CREATE OR REPLACE FUNCTION public.touch_broadcast(p_room_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.rooms SET live_started_at = now()
    WHERE id = p_room_id AND live_uid = auth.uid();
  UPDATE public.room_broadcasters SET started_at = now()
    WHERE room_id = p_room_id AND user_id = auth.uid();
END;
$function$

-- snapshot-fn: touch_call
CREATE OR REPLACE FUNCTION public.touch_call(p_call_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.calls
     set last_seen_at = now()
   where id = p_call_id
     and ended_at is null
     and auth.uid() in (caller_id, callee_id);
end;
$function$

-- snapshot-fn: trg_ban_nickname
CREATE OR REPLACE FUNCTION public.trg_ban_nickname()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public.is_banned_nickname(new.nickname)
     and not public.is_admin_request() then
    raise exception 'nickname_banned';
  end if;
  return new;
end;
$function$

-- snapshot-fn: trg_coin_ledger_balance
CREATE OR REPLACE FUNCTION public.trg_coin_ledger_balance()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.profiles set
    bonus_balance = bonus_balance + case when new.bucket='bonus' then new.amount else 0 end,
    topup_balance = topup_balance + case when new.bucket='topup' then new.amount else 0 end,
    earned_balance = earned_balance + case when new.bucket='earned' then new.amount else 0 end,
    points = points + new.amount
  where id=new.user_id;
  return new;
end; $function$

-- snapshot-fn: undo_message_v2
CREATE OR REPLACE FUNCTION public.undo_message_v2(p_message_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  cost int; owner uuid; r jsonb; has_is_deleted boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;

  select cost_undo_message into cost from app_settings where id = 'global';
  select sender_id into owner from public.private_messages where id = p_message_id;
  if owner is null then raise exception 'Message not found'; end if;
  if owner <> me then raise exception 'Bukan pesanmu'; end if;

  -- Cek kolom is_deleted (ditambahkan 20260923).
  select exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='private_messages'
       and column_name='is_deleted'
  ) into has_is_deleted;

  r := public.spend_yukcoin(me, 'undo_message', cost, p_message_id::text);

  if has_is_deleted then
    update public.private_messages
       set is_deleted = true, text = ''
     where id = p_message_id and sender_id = me;
  else
    delete from public.private_messages where id = p_message_id and sender_id = me;
  end if;

  return jsonb_build_object('ok', true, 'cost', cost,
    'remaining', (r->>'remaining')::int);
end; $function$

-- snapshot-fn: unfollow_user
CREATE OR REPLACE FUNCTION public.unfollow_user(p_followee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_followee is null then raise exception 'Invalid target'; end if;
  delete from follows where follower_id = me and followee_id = p_followee;
  -- Putus teman = benar-benar putus: hapus relasi friend_requests accepted
  -- maupun pending antara kedua pihak, supaya `_are_friends` (friend_requests
  -- accepted) SELARAS dengan `_privacy_are_friends` (follows). Tanpa ini,
  -- story mantan teman tetap terlihat (stale).
  delete from friend_requests
   where (from_id = me and to_id = p_followee)
      or (from_id = p_followee and to_id = me);
  return jsonb_build_object('ok', true, 'following', false);
end;
$function$

-- snapshot-fn: unlock_photo
CREATE OR REPLACE FUNCTION public.unlock_photo(p_photo_id uuid, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  points_on boolean; once_cost int; perm_cost int; owner_pct int; mult int;
  cost int; bonus_p int; owner_id uuid; owner_share int; remaining int;
  tier text; res jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_mode not in ('once','perm') then raise exception 'Invalid mode'; end if;

  select points_enabled, photo_unlock_once, photo_unlock_perm, photo_unlock_owner_pct,
         bonus_price_multiplier
    into points_on, once_cost, perm_cost, owner_pct, mult
    from app_settings where id = 'global';

  if points_on is false then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  select user_id into owner_id from user_photos where id = p_photo_id;
  if owner_id is null then raise exception 'Photo not found'; end if;
  if owner_id = me then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  cost := case p_mode when 'perm' then perm_cost else once_cost end;
  bonus_p := cost * mult;

  if exists (select 1 from photo_unlocks where viewer_id = me and photo_id = p_photo_id) then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  res := public.ledger_spend_dual(me, 'photo_unlock', cost, bonus_p, p_photo_id::text);
  tier := res->>'tier';
  remaining := (res->>'remaining')::int;

  owner_share := (cost * owner_pct) / 100;
  if owner_share > 0 then
    perform public.ledger_credit(owner_id,
      case when tier = 'paid' then 'earned' else 'bonus' end,
      'photo_income', owner_share, p_photo_id::text,
      jsonb_build_object('viewer', me, 'mode', p_mode, 'tier', tier));
  end if;
  if tier = 'paid' then
    insert into platform_revenue (source, amount, metadata)
      values ('photo_unlock', cost - owner_share,
              jsonb_build_object('photo_id', p_photo_id, 'mode', p_mode, 'viewer', me, 'owner', owner_id));
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (me, 'photo_unlock', -case when tier = 'paid' then cost else bonus_p end,
            jsonb_build_object('photo_id', p_photo_id, 'mode', p_mode, 'tier', tier));

  if p_mode = 'perm' then
    insert into photo_unlocks (viewer_id, photo_id) values (me, p_photo_id)
      on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'points', remaining, 'mode', p_mode, 'tier', tier);
end; $function$

-- snapshot-fn: unmute_story_author
CREATE OR REPLACE FUNCTION public.unmute_story_author(p_author uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  delete from public.story_mutes
   where muter_id = me and muted_id = p_author;
end; $function$

-- snapshot-fn: unsubscribe_creator
CREATE OR REPLACE FUNCTION public.unsubscribe_creator(p_creator uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  delete from subscriptions where subscriber_id = me and creator_id = p_creator;
  return jsonb_build_object('ok', true);
end; $function$

-- snapshot-fn: update_device_fcm_token
CREATE OR REPLACE FUNCTION public.update_device_fcm_token(p_install_id text, p_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_install_id is null or p_install_id = '' then
    return;
  end if;

  -- upsert minimal baris device jika belum ada (mis. token datang sebelum upsert_device)
  insert into public.user_devices (user_id, install_id, fcm_token, last_seen_at, is_active)
    values (uid, p_install_id, coalesce(p_token,''), now(), true)
  on conflict (user_id, install_id)
  do update set fcm_token = excluded.fcm_token, last_seen_at = now(), is_active = true;

  -- sync juga ke profiles untuk kompatibilitas client lama yang masih baca profiles.fcm_token
  update public.profiles set fcm_token = coalesce(p_token,'') where id = uid;
end;
$function$

-- snapshot-fn: update_my_location
CREATE OR REPLACE FUNCTION public.update_my_location(p_lat double precision, p_lon double precision, p_source text, p_ip text DEFAULT NULL::text, p_mocked boolean DEFAULT false, p_accuracy integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  v_ip text := nullif(trim(coalesce(p_ip, '')), '');
  v_last_lat double precision;
  v_last_lon double precision;
  v_last_at timestamptz;
  v_reason text := null;
  v_flag boolean := false;
  v_speed_mps double precision;
  v_same_streak int;
  v_shared int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('gps', 'ip') then
    raise exception 'Invalid source';
  end if;

  -- Heuristik (hanya relevan untuk source gps; IP = perkiraan, tak dinilai).
  if p_source = 'gps' then
    -- (a) device melaporkan mock provider.
    if coalesce(p_mocked, false) then
      v_flag := true; v_reason := 'is_mocked';
    end if;
    -- (b) akurasi 0 / negatif persis (khas mock).
    if p_accuracy is not null and p_accuracy <= 0 then
      v_flag := true;
      v_reason := case when v_reason is null then 'accuracy_zero'
                       else v_reason || ',accuracy_zero' end;
    end if;

    -- Ambil titik GPS terakhir (untuk c & e).
    select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
      from public.user_location_history
     where user_id = uid and loc_source = 'gps'
     order by created_at desc limit 1;

    -- (c) kecepatan mustahil (>250 m/s ≈ 900 km/jam) dari titik terakhir.
    if found and v_last_at is not null
       and now() - v_last_at >= interval '10 seconds' then
      v_speed_mps := earth_distance(
        ll_to_earth(v_last_lat, v_last_lon), ll_to_earth(p_lat, p_lon))
        / extract(epoch from (now() - v_last_at));
      if v_speed_mps > 250 then
        v_flag := true;
        v_reason := case when v_reason is null then 'impossible_speed'
                         else v_reason || ',impossible_speed' end;
      end if;
    end if;

    -- (d) GPS vs IP terakhir berbeda > 500 km (spoof).
    if exists (
      select 1 from public.profiles
      where id = uid and lat_ip is not null and lon_ip is not null)
    then
      if (
        select earth_distance(ll_to_earth(lat_ip, lon_ip), ll_to_earth(p_lat, p_lon))
        from public.profiles where id = uid) > 500000 then
        v_flag := true;
        v_reason := case when v_reason is null then 'spoof_delta'
                         else v_reason || ',spoof_delta' end;
      end if;
    end if;

    -- (f) koordinat ≈ default emulator (radius 100 m). Default khas:
    --     Android Emulator (Googleplex), dan default SDK lain yang lazim.
    if (earth_distance(ll_to_earth(37.4220, -122.0841), ll_to_earth(p_lat, p_lon)) < 100)
       or (earth_distance(ll_to_earth(37.4219983, -122.084), ll_to_earth(p_lat, p_lon)) < 100)
       or (earth_distance(ll_to_earth(0, 0), ll_to_earth(p_lat, p_lon)) < 100) then
      v_flag := true;
      v_reason := case when v_reason is null then 'known_emulator'
                       else v_reason || ',known_emulator' end;
    end if;

    -- (e) static_coord: 3 update GPS terakhir berturut identik (< 8 m) →
    --     koordinat beku (khas emulator/static fake). Dihitung dari history.
    select count(*) into v_same_streak
      from (
        select lat, lon
          from public.user_location_history
         where user_id = uid and loc_source = 'gps'
         order by created_at desc limit 3
      ) h
     where earth_distance(ll_to_earth(h.lat, h.lon), ll_to_earth(p_lat, p_lon)) < 8;
    if v_same_streak >= 3 then
      v_flag := true;
      v_reason := case when v_reason is null then 'static_coord'
                       else v_reason || ',static_coord' end;
    end if;

    -- (g) shared_coord: koordinat (< 25 m) dipakai ≥3 user BERBEDA → farm.
    select count(distinct p.id) into v_shared
      from public.profiles p
     where p.id <> uid
       and p.lat_gps is not null
       and earth_distance(ll_to_earth(p.lat_gps, p.lon_gps), ll_to_earth(p_lat, p_lon)) < 25;
    if v_shared >= 2 then  -- 2 lain + diri = 3 total
      v_flag := true;
      v_reason := case when v_reason is null then 'shared_coord'
                       else v_reason || ',shared_coord' end;
    end if;
  end if;

  if p_source = 'gps' then
    update public.profiles
       set lat_gps        = p_lat,
           lon_gps        = p_lon,
           gps_updated_at = now(),
           lat            = p_lat,
           lon            = p_lon,
           loc_source     = 'gps',
           loc_updated_at = now(),
           location_mocked      = v_flag,
           location_mock_reason = v_reason,
           location_accuracy_m  = p_accuracy,
           location_flagged_at  = case when v_flag then now()
                                       else location_flagged_at end
     where id = uid;
  else
    update public.profiles
       set lat_ip        = p_lat,
           lon_ip        = p_lon,
           ip_updated_at = now(),
           ip_address    = coalesce(v_ip, ip_address),
           lat           = coalesce(lat_gps, p_lat),
           lon           = coalesce(lon_gps, p_lon),
           loc_source    = case when lat_gps is not null then 'gps' else 'ip' end,
           loc_updated_at = now()
     where id = uid;
  end if;

  -- History: lewati bila diam (<50m) & titik terakhir masih segar (<30 mnt),
  -- TAPI tetap catat bila ada flag mock (agar riwayat audit tak bolong).
  select lat, lon, created_at into v_last_lat, v_last_lon, v_last_at
    from public.user_location_history
   where user_id = uid
   order by created_at desc limit 1;
  if found
     and earth_distance(
           ll_to_earth(v_last_lat, v_last_lon),
           ll_to_earth(p_lat, p_lon)) < 50
     and now() - v_last_at < interval '30 minutes'
     and not v_flag then
    return;
  end if;
  insert into public.user_location_history
    (user_id, lat, lon, loc_source, location_mocked, mock_reason, accuracy_m)
  values (uid, p_lat, p_lon, p_source, v_flag, v_reason, p_accuracy);
end;
$function$

-- snapshot-fn: update_privacy_settings
CREATE OR REPLACE FUNCTION public.update_privacy_settings(p_presence text DEFAULT NULL::text, p_last_seen text DEFAULT NULL::text, p_profile_photo text DEFAULT NULL::text, p_about text DEFAULT NULL::text, p_story text DEFAULT NULL::text, p_read_receipts boolean DEFAULT NULL::boolean, p_leaderboard text DEFAULT NULL::text, p_call text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_allowed text[] := array['everyone','everyone_except','friends','friends_except','only','nobody'];
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_presence is not null and not (p_presence = any(v_allowed)) then
    raise exception 'Invalid presence visibility';
  end if;
  if p_last_seen is not null and not (p_last_seen = any(v_allowed)) then
    raise exception 'Invalid last seen visibility';
  end if;
  if p_profile_photo is not null and not (p_profile_photo = any(v_allowed)) then
    raise exception 'Invalid profile photo visibility';
  end if;
  if p_about is not null and not (p_about = any(v_allowed)) then
    raise exception 'Invalid about visibility';
  end if;
  if p_story is not null and not (p_story = any(v_allowed)) then
    raise exception 'Invalid story visibility';
  end if;
  if p_leaderboard is not null and not (p_leaderboard = any(v_allowed)) then
    raise exception 'Invalid leaderboard visibility';
  end if;
  if p_call is not null and not (p_call = any(v_allowed)) then
    raise exception 'Invalid call visibility';
  end if;

  if p_presence = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'presence') then
    raise exception 'only requires at least one person';
  end if;
  if p_last_seen = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'last_seen') then
    raise exception 'only requires at least one person';
  end if;
  if p_profile_photo = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'profile_photo') then
    raise exception 'only requires at least one person';
  end if;
  if p_about = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'about') then
    raise exception 'only requires at least one person';
  end if;
  if p_story = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'story') then
    raise exception 'only requires at least one person';
  end if;
  if p_leaderboard = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'leaderboard') then
    raise exception 'only requires at least one person';
  end if;
  if p_call = 'only' and not exists (
      select 1 from public.profile_privacy_exclusions
      where owner_id = auth.uid() and field = 'call') then
    raise exception 'only requires at least one person';
  end if;

  update profiles set
    presence_visibility = coalesce(p_presence, presence_visibility),
    last_seen_visibility = coalesce(p_last_seen, last_seen_visibility),
    profile_photo_visibility = coalesce(p_profile_photo, profile_photo_visibility),
    about_visibility = coalesce(p_about, about_visibility),
    story_visibility = coalesce(p_story, story_visibility),
    leaderboard_visibility = coalesce(p_leaderboard, leaderboard_visibility),
    call_visibility = coalesce(p_call, call_visibility),
    read_receipts_enabled = coalesce(p_read_receipts, read_receipts_enabled)
  where id = auth.uid();
  return public.my_privacy_settings();
end;
$function$

-- snapshot-fn: update_room_icon
CREATE OR REPLACE FUNCTION public.update_room_icon(p_room_id text, p_icon text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_role text;
  v_icon text := btrim(coalesce(p_icon, ''));
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'unauthenticated');
  end if;
  if p_room_id is null or btrim(p_room_id) = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_room');
  end if;
  if v_icon = '' or length(v_icon) > 512 then
    return jsonb_build_object('ok', false, 'reason', 'bad_icon');
  end if;

  select owner_id into v_owner from public.rooms where id = p_room_id;
  if v_owner is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  v_role := public.fn_room_role(v_uid, p_room_id);
  if v_uid <> v_owner and coalesce(v_role, '') not in ('owner', 'admin') then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;

  update public.rooms set icon = v_icon where id = p_room_id;
  return jsonb_build_object('ok', true, 'icon', v_icon);
end;
$function$

-- snapshot-fn: upsert_device
CREATE OR REPLACE FUNCTION public.upsert_device(p_install_id text, p_brand text, p_model text, p_os_name text, p_os_version text, p_app_version text, p_ip text, p_nickname text DEFAULT ''::text, p_legacy_install_id text DEFAULT ''::text, p_attr_source text DEFAULT ''::text, p_utm_source text DEFAULT ''::text, p_utm_medium text DEFAULT ''::text, p_utm_campaign text DEFAULT ''::text, p_utm_content text DEFAULT ''::text, p_referrer_raw text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  v_new text := coalesce(nullif(trim(p_install_id), ''), 'unknown');
  v_legacy text := nullif(trim(coalesce(p_legacy_install_id, '')), '');
  new_id uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Migrasi in-place: baris lama (install_id legacy) milik user yang SAMA
  -- dipindah ke install_id baru → 1 HP fisik tetap 1 baris.
  if v_legacy is not null and v_legacy <> v_new then
    delete from public.user_devices d
     where d.user_id = uid
       and d.install_id = v_legacy
       and exists (
         select 1 from public.user_devices x
          where x.user_id = uid and x.install_id = v_new
       );
    update public.user_devices
       set install_id = v_new
     where user_id = uid
       and install_id = v_legacy;
  end if;

  insert into public.user_devices
    (user_id, install_id, brand, model, os_name, os_version, app_version,
     ip_address, nickname_snapshot, last_seen_at, is_active,
     attribution_source, utm_source, utm_medium, utm_campaign, utm_content,
     referrer_raw, attribution_at)
  values
    (uid, v_new, p_brand, p_model, p_os_name, p_os_version, p_app_version,
     p_ip, nullif(p_nickname, ''), now(), true,
     nullif(p_attr_source,''), nullif(p_utm_source,''), nullif(p_utm_medium,''),
     nullif(p_utm_campaign,''), nullif(p_utm_content,''), nullif(p_referrer_raw,''),
     case when nullif(p_attr_source,'') is not null then now() else null end)
  on conflict (user_id, install_id)
  do update set
    brand             = excluded.brand,
    model             = excluded.model,
    os_name           = excluded.os_name,
    os_version        = excluded.os_version,
    app_version       = excluded.app_version,
    ip_address        = excluded.ip_address,
    nickname_snapshot = coalesce(excluded.nickname_snapshot,
                                 public.user_devices.nickname_snapshot),
    last_seen_at      = excluded.last_seen_at,
    is_active         = true,
    -- TULIS SEKALI: hanya isi bila kolom existing masih NULL DAN param baru ada.
    attribution_source = coalesce(public.user_devices.attribution_source, excluded.attribution_source),
    utm_source         = coalesce(public.user_devices.utm_source, excluded.utm_source),
    utm_medium         = coalesce(public.user_devices.utm_medium, excluded.utm_medium),
    utm_campaign       = coalesce(public.user_devices.utm_campaign, excluded.utm_campaign),
    utm_content        = coalesce(public.user_devices.utm_content, excluded.utm_content),
    referrer_raw       = coalesce(public.user_devices.referrer_raw, excluded.referrer_raw),
    attribution_at     = coalesce(public.user_devices.attribution_at, excluded.attribution_at)
  returning id into new_id;

  -- Bersihkan duplikat lama (sisa identifier lama) — perilaku LIVE dipertahankan.
  delete from public.user_devices
  where user_id = uid
    and lower(brand) = lower(p_brand)
    and lower(model) = lower(p_model)
    and install_id != v_new
    and id != coalesce(new_id, '00000000-0000-0000-0000-000000000000'::uuid);
end;
$function$

-- snapshot-fn: user_counts
CREATE OR REPLACE FUNCTION public.user_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_excl uuid[];
  v_dummy uuid[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  return jsonb_build_object(
    'registered', (select count(*) from public.profiles
      where is_registered = true
        and not (id = any(v_excl))
        and not (id = any(v_dummy))),
    'anon', (select count(*) from public.profiles
      where is_registered = false
        and not (id = any(v_excl))
        and not (id = any(v_dummy))
        and coalesce(needs_onboarding, false) = false)
  );
end;
$function$

-- snapshot-fn: user_fcm_tokens
CREATE OR REPLACE FUNCTION public.user_fcm_tokens(p_uid uuid)
 RETURNS SETOF text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with dev as (
    select d.fcm_token
      from public.user_devices d
     where d.user_id = p_uid
       and d.is_active = true
       and coalesce(d.fcm_token,'') <> ''
  )
  select fcm_token from dev
  union
  select coalesce(p.fcm_token,'')
    from public.profiles p
   where p.id = p_uid
     and coalesce(p.fcm_token,'') <> ''
     and not exists (select 1 from dev);
$function$

-- snapshot-fn: verified_uids
CREATE OR REPLACE FUNCTION public.verified_uids(p_uids uuid[])
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(array_agg(p.id), '{}'::uuid[])
  from public.profiles p
  where p.id = any(p_uids)
    and p.phone_verified_at is not null;
$function$

-- snapshot-fn: vote_poll
CREATE OR REPLACE FUNCTION public.vote_poll(p_message_id bigint, p_options integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_chat text;
  v_poll jsonb;
  v_n int;
  v_opts int[] := coalesce(p_options, '{}');
  v_i int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select m.chat_id, m.poll into v_chat, v_poll
  from public.private_messages m
  join public.private_chats pc on pc.chat_id = m.chat_id
  where m.id = p_message_id
    and m.type = 'poll'
    and coalesce(m.is_deleted, false) = false
    and auth.uid() = any (pc.participants);
  if v_chat is null or v_poll is null then
    raise exception 'poll not found';
  end if;

  v_n := jsonb_array_length(v_poll->'o');
  -- Unik + dalam rentang.
  select coalesce(array_agg(distinct x order by x), '{}') into v_opts
  from unnest(v_opts) as x;
  foreach v_i in array v_opts loop
    if v_i < 0 or v_i >= v_n then
      raise exception 'invalid option';
    end if;
  end loop;
  if coalesce((v_poll->>'m')::boolean, false) = false
     and cardinality(v_opts) > 1 then
    raise exception 'single choice poll';
  end if;

  delete from public.chat_poll_votes
  where message_id = p_message_id and user_id = auth.uid();

  insert into public.chat_poll_votes (message_id, chat_id, user_id, option_idx)
  select p_message_id, v_chat, auth.uid(), x from unnest(v_opts) as x;

  return coalesce(public.get_poll_results(array[p_message_id]) -> 0, '{}'::jsonb);
end;
$function$

-- snapshot-fn: vote_room_poll
CREATE OR REPLACE FUNCTION public.vote_room_poll(p_message_id bigint, p_options integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_room text;
  v_poll jsonb;
  v_n int;
  v_opts int[] := coalesce(p_options, '{}');
  v_i int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select m.room_id, m.poll into v_room, v_poll
  from public.messages m
  where m.id = p_message_id
    and m.type = 'poll'
    and coalesce(m.is_deleted, false) = false
    and (
      (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
      or not exists (
        select 1 from public.rooms r
        where r.id = m.room_id and r.is_private = true
      )
      or exists (
        select 1 from public.room_members mm
        where mm.room_id = m.room_id and mm.user_id = auth.uid()
      )
    );
  if v_room is null or v_poll is null then
    raise exception 'poll not found';
  end if;

  v_n := jsonb_array_length(v_poll->'o');
  select coalesce(array_agg(distinct x order by x), '{}') into v_opts
  from unnest(v_opts) as x;
  foreach v_i in array v_opts loop
    if v_i < 0 or v_i >= v_n then
      raise exception 'invalid option';
    end if;
  end loop;
  if coalesce((v_poll->>'m')::boolean, false) = false
     and cardinality(v_opts) > 1 then
    raise exception 'single choice poll';
  end if;

  delete from public.room_poll_votes
  where message_id = p_message_id and user_id = auth.uid();

  insert into public.room_poll_votes (message_id, room_id, user_id, option_idx)
  select p_message_id, v_room, auth.uid(), x from unnest(v_opts) as x;

  return coalesce(
    public.get_room_poll_results(array[p_message_id]) -> 0,
    '{}'::jsonb
  );
end;
$function$

-- snapshot-fn: wallet_sync_points
CREATE OR REPLACE FUNCTION public.wallet_sync_points(p_user uuid)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select points from public.profiles where id=p_user;
$function$

-- snapshot-fn: week_label
CREATE OR REPLACE FUNCTION public.week_label(tz_offset_minutes integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select to_char(
    date_trunc('week', (now() + make_interval(mins => tz_offset_minutes)))::date,
    'IYYY-IW'
  );
$function$

-- snapshot-fn: week_start_utc
CREATE OR REPLACE FUNCTION public.week_start_utc(tz_offset_minutes integer)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select (
    date_trunc('week', (now() + make_interval(mins => tz_offset_minutes)))
    - make_interval(mins => tz_offset_minutes)
  );
$function$

-- snapshot-fn: withdrawal_summary
CREATE OR REPLACE FUNCTION public.withdrawal_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare res jsonb;
begin
  select jsonb_build_object('rate', withdraw_rate_idr, 'min_coins', withdraw_min_coins)
    into res from app_settings where id = 'global';
  return res;
end; $function$

-- snapshot-fn: yukcoin_total
CREATE OR REPLACE FUNCTION public.yukcoin_total(p_user uuid)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(amount), 0)::int from public.coin_ledger where user_id = p_user;
$function$

-- snapshot-fn: yukcoin_v2_enabled_for
CREATE OR REPLACE FUNCTION public.yukcoin_v2_enabled_for(p_uid uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v boolean;
begin
  select yukcoin_v2_enabled into v from app_settings where id = 'global';
  if v is true then return true; end if;
  -- Admin selalu boleh (test/dev).
  if coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com' then
    return true;
  end if;
  return false;
end; $function$

-- snapshot-fn: yukcoin_v2_status
CREATE OR REPLACE FUNCTION public.yukcoin_v2_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  e int; b int; g boolean; ex int;
begin
  if me is null then
    return jsonb_build_object('active', false, 'total', 0,
      'ghost', false, 'extra_slots', 0);
  end if;
  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b from public.coin_ledger where user_id = me;
  select exists (select 1 from public.ghost_mode_active
                  where user_id = me and expires_at > now()) into g;
  select coalesce((select extra from public.photo_slots_unlocked
                    where user_id = me), 0) into ex;
  return jsonb_build_object(
    'active', public.yukcoin_v2_enabled_for(me),
    'total', (e + b),
    'bonus', b,
    'earned', e,
    'ghost', coalesce(g, false),
    'extra_slots', coalesce(ex, 0)
  );
end; $function$
