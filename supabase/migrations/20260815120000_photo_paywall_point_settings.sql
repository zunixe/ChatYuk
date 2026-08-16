-- ============================================================
-- ChatYuk: Foto galeri berbayar koin + nominal poin dapat diatur admin
--
-- - Nominal poin (bonus/cost/photo) dipindah ke app_settings agar admin
--   bisa mengatur dari panel. Fungsi bonus/cost dibuat membaca settings.
-- - Foto galeri: index 0 gratis dilihat orang; index 1..5 terkunci.
--   Buka: 'once' (lihat sekali) / 'perm' (permanen). WAJIB pakai koin
--   bucket 'topup' (yang dibeli). 60% ke pemilik (earned), 40% hangus.
-- - Upload slot 1..5 memberi reward koin (bucket bonus) sekali per slot.
-- - Foto terkunci tidak dikirim penuh ke client — hanya preview blur
--   (kolom photo_preview) yang dikirim; foto asli hanya saat sudah unlock.
-- ============================================================

-- 1. Kolom nominal di app_settings (idempoten, dengan default).
alter table public.app_settings
  add column if not exists photo_upload_reward int not null default 5,
  add column if not exists photo_unlock_once int not null default 5,
  add column if not exists photo_unlock_perm int not null default 20,
  add column if not exists photo_unlock_owner_pct int not null default 60,
  add column if not exists bonus_registered int not null default 100,
  add column if not exists bonus_rated int not null default 20,
  add column if not exists bonus_shared int not null default 10,
  add column if not exists bonus_profile int not null default 10,
  add column if not exists bonus_first_photo int not null default 10,
  add column if not exists bonus_room_read int not null default 2,
  add column if not exists bonus_new_chat int not null default 5,
  add column if not exists cost_chat_text int not null default 1,
  add column if not exists cost_chat_image int not null default 3,
  add column if not exists cost_view_once int not null default 3;

-- 2. Kolom preview blur di user_photos (base64 low-res blur).
alter table public.user_photos
  add column if not exists photo_preview text;

-- 3. Tabel photo_unlocks (buka permanen).
create table if not exists public.photo_unlocks (
  viewer_id  uuid not null references auth.users(id) on delete cascade,
  photo_id   uuid not null references public.user_photos(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (viewer_id, photo_id)
);
alter table public.photo_unlocks enable row level security;
drop policy if exists photo_unlocks_select_own on public.photo_unlocks;
create policy photo_unlocks_select_own on public.photo_unlocks
  for select using (viewer_id = auth.uid());

-- 4. Helper: potong HANYA dari bucket 'topup' (koin yang dibeli).
create or replace function public.ledger_spend_topup(
  p_user uuid, p_type text, p_amount int, p_ref text default null
) returns int language plpgsql security definer set search_path = public as $$
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
end; $$;
grant execute on function public.ledger_spend_topup(uuid, text, int, text) to authenticated, service_role;

-- 5. RPC: reward upload slot 1..5 (bonus bucket), sekali per slot.
create or replace function public.reward_photo_slot(p_slot_index int)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; reward int; tot int; action_key text;
begin
  select points_enabled, photo_upload_reward into points_on, reward
    from app_settings where id = 'global';
  if points_on is false or p_slot_index < 1 or p_slot_index > 5 then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  action_key := 'photo_slot_' || p_slot_index::text;
  if exists (select 1 from profiles where id = auth.uid()
             and one_time_actions->>action_key = 'true') then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
    where id = auth.uid();
  tot := public.ledger_credit(auth.uid(), 'bonus', 'photo_upload', reward,
           null, jsonb_build_object('slot', p_slot_index));
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'photo_upload', reward, jsonb_build_object('slot', p_slot_index));
  return tot;
end; $$;
grant execute on function public.reward_photo_slot(int) to authenticated, service_role;

-- 6. RPC: unlock foto (mode 'once' | 'perm'). Wajib koin topup.
create or replace function public.unlock_photo(p_photo_id uuid, p_mode text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  points_on boolean; once_cost int; perm_cost int; owner_pct int;
  cost int; owner_id uuid; owner_share int; remaining int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_mode not in ('once','perm') then raise exception 'Invalid mode'; end if;

  select points_enabled, photo_unlock_once, photo_unlock_perm, photo_unlock_owner_pct
    into points_on, once_cost, perm_cost, owner_pct
    from app_settings where id = 'global';

  -- Kalau sistem koin mati, semua terbuka gratis.
  if points_on is false then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  select user_id into owner_id from user_photos where id = p_photo_id;
  if owner_id is null then raise exception 'Photo not found'; end if;
  if owner_id = me then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  cost := case p_mode when 'perm' then perm_cost else once_cost end;

  -- Sudah unlock permanen? tak perlu bayar lagi.
  if exists (select 1 from photo_unlocks where viewer_id = me and photo_id = p_photo_id) then
    return jsonb_build_object('ok', true, 'points', (select points from profiles where id = me));
  end if;

  -- Potong koin topup viewer (raise 'Not enough topup' bila kurang).
  remaining := public.ledger_spend_topup(me, 'photo_unlock', cost,
                 p_photo_id::text);

  -- Bagi hasil: owner_pct% ke pemilik (earned), sisanya hangus (platform).
  owner_share := (cost * owner_pct) / 100;
  if owner_share > 0 then
    perform public.ledger_credit(owner_id, 'earned', 'photo_income', owner_share,
              p_photo_id::text, jsonb_build_object('viewer', me, 'mode', p_mode));
  end if;
  -- Catat pendapatan platform (bagian hangus).
  insert into platform_revenue (source, amount, metadata)
    values ('photo_unlock', cost - owner_share,
            jsonb_build_object('photo_id', p_photo_id, 'mode', p_mode, 'viewer', me, 'owner', owner_id));

  insert into point_events (user_id, event, amount, metadata)
    values (me, 'photo_unlock', -cost, jsonb_build_object('photo_id', p_photo_id, 'mode', p_mode));

  if p_mode = 'perm' then
    insert into photo_unlocks (viewer_id, photo_id) values (me, p_photo_id)
      on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'points', remaining, 'mode', p_mode);
end; $$;
revoke execute on function public.unlock_photo(uuid, text) from public, anon;
grant execute on function public.unlock_photo(uuid, text) to authenticated;

-- 7. RPC: ambil foto user lain + flag akses. Foto terkunci TIDAK mengembalikan
--    photo asli (hanya preview blur). Index 0 selalu terbuka.
create or replace function public.get_user_photos_access(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end; $$;
revoke execute on function public.get_user_photos_access(uuid) from public, anon;
grant execute on function public.get_user_photos_access(uuid) to authenticated;

-- 8. RPC: admin update nominal poin.
create or replace function public.admin_update_point_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    photo_upload_reward   = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once     = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm     = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct= coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    bonus_registered      = coalesce((p->>'bonus_registered')::int, bonus_registered),
    bonus_rated           = coalesce((p->>'bonus_rated')::int, bonus_rated),
    bonus_shared          = coalesce((p->>'bonus_shared')::int, bonus_shared),
    bonus_profile         = coalesce((p->>'bonus_profile')::int, bonus_profile),
    bonus_first_photo     = coalesce((p->>'bonus_first_photo')::int, bonus_first_photo),
    bonus_room_read       = coalesce((p->>'bonus_room_read')::int, bonus_room_read),
    bonus_new_chat        = coalesce((p->>'bonus_new_chat')::int, bonus_new_chat),
    cost_chat_text        = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image       = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once        = coalesce((p->>'cost_view_once')::int, cost_view_once),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_update_point_settings(jsonb) from public, anon;
grant execute on function public.admin_update_point_settings(jsonb) to authenticated, service_role;

-- 9. RPC: ambil setting poin (untuk admin panel).
create or replace function public.admin_get_point_settings()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  return (select jsonb_build_object(
    'photo_upload_reward', photo_upload_reward,
    'photo_unlock_once', photo_unlock_once,
    'photo_unlock_perm', photo_unlock_perm,
    'photo_unlock_owner_pct', photo_unlock_owner_pct,
    'bonus_registered', bonus_registered,
    'bonus_rated', bonus_rated,
    'bonus_shared', bonus_shared,
    'bonus_profile', bonus_profile,
    'bonus_first_photo', bonus_first_photo,
    'bonus_room_read', bonus_room_read,
    'bonus_new_chat', bonus_new_chat,
    'cost_chat_text', cost_chat_text,
    'cost_chat_image', cost_chat_image,
    'cost_view_once', cost_view_once
  ) from app_settings where id = 'global');
end; $$;
revoke execute on function public.admin_get_point_settings() from public, anon;
grant execute on function public.admin_get_point_settings() to authenticated, service_role;

-- 10. Nominal-driven: deduct_chat_point, room_read_bonus, new_chat_bonus
--     baca dari app_settings.
create or replace function public.deduct_chat_point(msg_type text)
returns int language plpgsql security definer set search_path = public as $$
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
end; $$;
grant execute on function public.deduct_chat_point(text) to authenticated, service_role;

create or replace function public.room_read_bonus()
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; ok boolean; tot int; rr int;
begin
  select points_enabled, bonus_room_read into points_on, rr from app_settings where id = 'global';
  if points_on is false then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  update profiles set room_reads_today = room_reads_today + 1
    where id = auth.uid() and room_reads_today < 5;
  ok := found;
  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'room_read', rr);
    insert into point_events (user_id, event, amount) values (auth.uid(), 'room_read', rr);
    return tot;
  end if;
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.room_read_bonus() to authenticated, service_role;

create or replace function public.new_chat_bonus(other_uid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare points_on boolean; tot int; ok boolean; nc int;
begin
  select points_enabled, bonus_new_chat into points_on, nc from app_settings where id = 'global';
  if points_on is false then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  if exists (select 1 from point_events where user_id = auth.uid()
             and event = 'new_chat' and metadata->>'other_uid' = other_uid::text) then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  update profiles set new_chats_today = new_chats_today + 1
    where id = auth.uid() and new_chats_today < 3;
  ok := found;
  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'new_chat', nc,
             null, jsonb_build_object('other_uid', other_uid));
    insert into point_events (user_id, event, amount, metadata)
      values (auth.uid(), 'new_chat', nc, jsonb_build_object('other_uid', other_uid));
    return tot;
  end if;
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $$;
grant execute on function public.new_chat_bonus(uuid) to authenticated, service_role;
