-- ============================================================
-- FIX: create_private_room — admin (zunixe@gmail.com) bebas koin & bebas limit.
--
-- Migrasi 20260815010000_points_admin_dev_bypass.sql [11] menimpa versi
-- admin-free (20260814190000) dan salah lagi:
--   `if points_on is not false or is_admin then <charge>`
--   → admin JUSTRU selalu kena charge saat points ON, dan limit 2 room
--     tetap berlaku untuk admin. Akibatnya: "koin tidak cukup" saat pakai
--     password (butuh 150), dan admin tidak bisa buat room saat points ON.
--
-- Aturan benar:
--   - Admin: tidak pernah dipotong koin, tidak kena limit 2 room.
--   - User biasa (points ON): dipotong 100 (tanpa pw) / 150 (dengan pw).
--   - User biasa (points OFF): gratis (produksi aman, tidak menyentuh koin).
-- ============================================================
begin;
create or replace function public.create_private_room(
  p_name text,
  p_icon text,
  p_country text,
  p_password text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  points_on boolean;
  cost int;
  has_pw boolean := (p_password is not null and length(p_password) > 0);
  active_count int;
  new_id text;
  my_name text;
  remaining int;
  is_admin boolean := (coalesce(auth.email(), '') = 'zunixe@gmail.com');
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then
    raise exception 'Invalid room name';
  end if;
  if p_country is null or p_country = '' then
    raise exception 'Invalid country';
  end if;

  -- limit 2 room aktif per user (admin bebas limit)
  if not is_admin then
    select count(*) into active_count from public.rooms
     where owner_id = uid and is_private = true
       and (expires_at is null or expires_at > now());
    if active_count >= 2 then
      raise exception 'Room limit reached';
    end if;
  end if;

  select points_enabled into points_on from public.app_settings where id = 'global';
  cost := case when has_pw then 150 else 100 end;

  -- Potong koin HANYA jika: points ON DAN bukan admin.
  if points_on is not false and not is_admin then
    select points into remaining from public.profiles where id = uid;
    if coalesce(remaining, 0) < cost then
      raise exception 'Not enough points';
    end if;
    update public.profiles set points = points - cost where id = uid
      returning points into remaining;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_create', -cost);
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  select nickname into my_name from public.profiles where id = uid;
  new_id := 'pr_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.rooms (id, name, description, icon, "order", country, category,
                            is_private, owner_id, owner_name, password_hash, has_password,
                            expires_at, created_at)
  values (new_id, p_name, '', coalesce(nullif(p_icon, ''), '🔒'), 999, p_country, 'private',
          true, uid, coalesce(my_name, 'Anon'),
          case when has_pw then crypt(p_password, gen_salt('bf')) else null end,
          has_pw, now() + interval '7 days', now());

  insert into public.room_members (room_id, user_id) values (new_id, uid)
    on conflict do nothing;

  return jsonb_build_object('id', new_id, 'points', coalesce(remaining, 0));
end;
$$;
commit;
