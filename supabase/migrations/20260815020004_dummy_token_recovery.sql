-- ── 20004: Token guard fix + recovery of broken dummy accounts ──

-- 1. GUARD FIX
create or replace function public.admin_update_dummy_token(p_uid uuid, p_refresh_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com'
     and auth.role() != 'service_role'
     and auth.uid() != p_uid then
    raise exception 'Unauthorized';
  end if;
  update public.dummy_accounts set refresh_token = p_refresh_token where uid = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.admin_update_dummy_token(uuid, text) from public, anon;
grant execute on function public.admin_update_dummy_token(uuid, text) to authenticated, service_role;

-- 2. RECOVERY
do $$
declare
  old_maria uuid := '9d5a92a6-e3c0-4039-8fe4-71221917b36b';
  old_sandra uuid := '495dca76-3ddc-4ccc-88f9-2fbc8ec36ae9';
  new_maria uuid := gen_random_uuid();
  new_sandra uuid := gen_random_uuid();
  sid uuid;
  maria_rt text;
  sandra_rt text;
  old_maria_nick text;
  old_sandra_nick text;
  old_maria_gender text; old_maria_age int; old_maria_country text; old_maria_city text;
  old_sandra_gender text; old_sandra_age int; old_sandra_country text; old_sandra_city text;
begin
  -- Replay-guard: user Maria/Sandra lama hanya ada di prod, skip jika tidak ada
  if not exists (select 1 from auth.users where id = old_maria)
     or not exists (select 1 from auth.users where id = old_sandra) then
    return;
  end if;

  -- Save old profile data
  select nickname, gender, age, country, city
  into old_maria_nick, old_maria_gender, old_maria_age, old_maria_country, old_maria_city
  from public.profiles where id = old_maria;

  select nickname, gender, age, country, city
  into old_sandra_nick, old_sandra_gender, old_sandra_age, old_sandra_country, old_sandra_city
  from public.profiles where id = old_sandra;

  -- A. Create fresh anonymous auth.users
  insert into auth.users (id, aud, role, is_anonymous, is_sso_user, raw_app_meta_data, created_at, updated_at)
  values
    (new_maria, 'authenticated', 'authenticated', true, false,
     '{"provider":"anonymous","providers":["anonymous"]}'::jsonb, now(), now()),
    (new_sandra, 'authenticated', 'authenticated', true, false,
     '{"provider":"anonymous","providers":["anonymous"]}'::jsonb, now(), now());

  -- B. Create sessions + refresh_tokens for new users
  insert into auth.sessions (id, user_id, created_at, updated_at, not_after, aal, refreshed_at)
  values (gen_random_uuid(), new_maria, now(), now(), now() + interval '100 years', 'aal1', now())
  returning id into sid;
  insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, session_id)
  values ('00000000-0000-0000-0000-000000000000'::uuid,
    md5(random()::text || clock_timestamp()::text)::text, new_maria, false, now(), now(), sid)
  returning token into maria_rt;

  insert into auth.sessions (id, user_id, created_at, updated_at, not_after, aal, refreshed_at)
  values (gen_random_uuid(), new_sandra, now(), now(), now() + interval '100 years', 'aal1', now())
  returning id into sid;
  insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, session_id)
  values ('00000000-0000-0000-0000-000000000000'::uuid,
    md5(random()::text || clock_timestamp()::text)::text, new_sandra, false, now(), now(), sid)
  returning token into sandra_rt;

  -- C. Create new profiles with old data
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered,
    last_seen, login_at, created_at, has_password, hashtags, points)
  values
    (new_maria, coalesce(old_maria_nick,'Maria'), coalesce(old_maria_gender,'male'),
     coalesce(old_maria_age,25), coalesce(old_maria_country,'Indonesia'),
     coalesce(old_maria_city,'Jakarta'), 'offline', false, now(), now(), now(),
     false, '{}'::text[], 0),
    (new_sandra, coalesce(old_sandra_nick,'Sandra'), coalesce(old_sandra_gender,'male'),
     coalesce(old_sandra_age,25), coalesce(old_sandra_country,'Indonesia'),
     coalesce(old_sandra_city,'Jakarta'), 'offline', false, now(), now(), now(),
     false, '{}'::text[], 0);

  -- D. Update dummy_accounts with new uids + fresh tokens
  update public.dummy_accounts
  set uid = case nickname when 'Maria' then new_maria when 'Sandra' then new_sandra end,
      refresh_token = case nickname when 'Maria' then maria_rt when 'Sandra' then sandra_rt end
  where nickname in ('Maria','Sandra');

  -- E. Update private_chats: replace old uid → new uid
  update public.private_chats
  set participants = array_replace(
    array_replace(participants, old_maria, new_maria),
    old_sandra, new_sandra)
  where old_maria = any(participants) or old_sandra = any(participants);

  -- F. Update private_messages sender_id
  update public.private_messages set sender_id = new_maria where sender_id = old_maria;
  update public.private_messages set sender_id = new_sandra where sender_id = old_sandra;

  -- G. Delete old ghost auth.users (CASCADE deletes old profiles)
  delete from auth.users where id in (old_maria, old_sandra);

end;
$$;
