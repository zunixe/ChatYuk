-- ============================================================
-- Fix private room: cegah double-create, lupa password, dan join koin
-- ============================================================

-- 1) Cegah double-create: jika owner bikin room nama sama <10 detik, kembalikan id lama
create or replace function public.create_private_room(p_name text, p_icon text, p_country text, p_password text DEFAULT NULL::text)
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
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then raise exception 'Invalid room name'; end if;
  if p_country is null or p_country = '' then raise exception 'Invalid country'; end if;

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

  if points_on is not false and not is_admin then
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
  values (new_id, p_name, '', coalesce(nullif(p_icon, ''), '🔒'), 999, p_country, 'private',
          true, uid, coalesce(my_name, 'Anon'),
          case when has_pw then crypt(p_password, gen_salt('bf')) else null end,
          has_pw, now() + interval '7 days', now(),
          v_token, 20, true);

  insert into public.room_members (room_id, user_id, role)
  values (new_id, uid, 'owner') on conflict do nothing;

  return jsonb_build_object('id', new_id, 'points', coalesce(remaining, 0), 'join_token', v_token);
end; $function$;

-- 2) Reset password private room (owner only) - untuk lupa password
create or replace function public.reset_room_password(p_room_id text, p_new_password text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
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
$$;
revoke execute on function public.reset_room_password(text,text) from public, anon;
grant execute on function public.reset_room_password(text,text) to authenticated;

-- 3) Fix join: private room tidak kena biaya koin (hanya public room yang berbayar)
--    Overwrite join_private_room: skip ledger_spend untuk is_private = true
create or replace function public.join_private_room(p_room_id text, p_password text DEFAULT NULL::text)
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
end; $function$;
