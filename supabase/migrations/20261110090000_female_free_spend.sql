-- menyentuh: deduct_chat_point
-- menyentuh: create_private_room
-- menyentuh: extend_private_room
-- 2026-11-07: PEREMPUAN GRATIS SEMUA — hanya untuk mendapat penghasilan
-- (keputusan user). Fitur berbayar tidak memotong koin perempuan:
-- foto/view-once (deduct_chat_point), buat & perpanjang grup privat,
-- boost postingan, langganan kreator. Langganan dari perempuan TIDAK
-- memberi penghasilan ke kreator (tidak mencetak koin baru).
-- Body tiap fungsi = versi live; hanya cabang gender yang ditambahkan.

create or replace function public._is_female(p_user uuid)
 returns boolean
 language sql
 stable
 security definer
 set search_path to 'public'
as $$
  select coalesce((select gender = 'female' from public.profiles where id = p_user), false);
$$;
revoke execute on function public._is_female(uuid) from public, anon, authenticated;

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
  -- 2026-10-31: chat TEKS gratis untuk semua gender. Hanya foto & view-once
  -- yang berbayar (pendorong top-up male + income female dari unlock foto).
  cost := case msg_type
    when 'image' then c_img
    when 'view_once' then c_vo
    when 'view_once_expired' then 0
    else 0 end;
  -- Perempuan gratis semua.
  if public._is_female(auth.uid()) then cost := 0; end if;
  if cost = 0 then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;
  remaining := public.ledger_spend(auth.uid(), 'spend_chat', cost, msg_type);
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));
  return remaining;
end; $function$;

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
  -- Perempuan gratis semua.
  if points_on is not false and not is_admin and not v_is_category
     and not public._is_female(uid) then
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
$function$;

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

  -- Perempuan gratis semua.
  if points_on is not false and not public._is_female(uid) then
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
end; $function$;

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

  -- Perempuan gratis semua.
  if points_on is not false and not public._is_female(me) then
    res := public.ledger_spend_dual(me, 'post_boost', paid, bonus_p, p_post_id::text);
    remaining := (res->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = me;
  end if;

  update public.posts
    set is_boosted = true, boosted_at = now()
    where id = p_post_id;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0));
end; $function$;

CREATE OR REPLACE FUNCTION public.subscribe_creator(p_creator uuid, p_periods integer DEFAULT 1, p_expected_price integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); price int; cut_pct int; duration_days int; periods int;
  points_on boolean; am_registered boolean; remaining int; cost int; cut int; net int;
  expire timestamptz; v_free boolean;
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

  -- Koin beli/penghasilan dulu; male boleh menambal dengan bonus
  -- (×multiplier, plafon promo) — ledger_spend_promo (2026-11-10).
  -- Perempuan gratis semua: tidak bayar, kreator tidak dapat penghasilan.
  v_free := public._is_female(me);
  if v_free then
    cost := 0; cut := 0; net := 0;
    remaining := public.yukcoin_total(me);
  else
    remaining := public.ledger_spend_promo(me, 'subscribe', cost, p_creator::text,
      p_creator, 100 - cut_pct);
  end if;

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

  if not v_free then
  insert into point_events (user_id, event, amount, metadata)
    values (me, 'subscribe', -cost, jsonb_build_object('creator', p_creator, 'periods', periods));
  end if;

  return jsonb_build_object('ok', true, 'points', remaining, 'expires_at', expire,
    'net', net, 'cut', cut, 'charged', cost, 'free', v_free);
end; $function$;
