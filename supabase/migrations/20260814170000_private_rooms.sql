-- ============================================================
-- ChatYuk: Private Rooms (user-created rooms + koin + password)
--
-- Ekonomi koin:
--   buat room            = 100 koin (hangus)
--   buat room+password   = 150 koin (hangus)
--   masuk private room   =   5 koin (pertama kali; ke pemilik room)
--   perpanjang 7 hari    =  50 koin (hangus)
--   global room          = gratis
--
-- Aturan:
--   - maks 2 room aktif per user
--   - room aktif 7 hari (expires_at), bisa diperpanjang
--   - ikut negara aktif (sama seperti global room)
--   - password di-hash bcrypt (pgcrypto). password_hash TIDAK pernah
--     ter-select ke client (column-level grant).
--   - fee masuk (5) dari joiner ANONIM hangus, tidak ke owner
--     (anti-farming: akun anonim dapat 50 koin gratis).
--   - RLS messages/room_presence diperketat: room private hanya
--     boleh diakses member (ada baris di room_members). Admin bypass.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ── Kolom baru di rooms ──
alter table public.rooms
  add column if not exists is_private   boolean     not null default false,
  add column if not exists owner_id     uuid,
  add column if not exists owner_name   text        not null default '',
  add column if not exists password_hash text,
  add column if not exists has_password boolean     not null default false,
  add column if not exists expires_at   timestamptz,
  add column if not exists created_at   timestamptz not null default now();

create index if not exists rooms_private_country_idx
  on public.rooms (country, expires_at) where is_private = true;

-- ── Tabel room_members (siapa yang sudah lolos password / join) ──
create table if not exists public.room_members (
  room_id   text not null references public.rooms (id) on delete cascade,
  user_id   uuid not null,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.room_members enable row level security;

drop policy if exists room_members_select on public.room_members;
create policy room_members_select on public.room_members
  for select using (true);

-- INSERT/DELETE hanya lewat RPC security definer (bukan langsung dari client)
drop policy if exists room_members_no_direct_write on public.room_members;

-- ============================================================
-- Column-level grant: sembunyikan password_hash dari client.
-- Pola sama seperti profiles (20260812200000_hardening_rls.sql).
-- ============================================================
revoke select on public.rooms from anon, authenticated;
grant select (id, name, description, icon, "order", country, category,
              is_private, owner_id, owner_name, has_password, expires_at, created_at)
  on public.rooms to anon, authenticated;

-- ============================================================
-- Perketat RLS messages: room private hanya untuk member/admin.
-- ============================================================
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select using (
    (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
    or not exists (
      select 1 from public.rooms r
      where r.id = messages.room_id and r.is_private = true
    )
    or exists (
      select 1 from public.room_members m
      where m.room_id = messages.room_id and m.user_id = auth.uid()
    )
  );

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert with check (
    auth.uid() = sender_id
    and (
      not exists (
        select 1 from public.rooms r
        where r.id = messages.room_id and r.is_private = true
      )
      or exists (
        select 1 from public.room_members m
        where m.room_id = messages.room_id and m.user_id = auth.uid()
      )
    )
  );

-- ============================================================
-- Perketat room_presence: join presence room private butuh membership.
-- ============================================================
drop policy if exists "room_presence_insert_own" on public.room_presence;
create policy "room_presence_insert_own" on public.room_presence
  for insert with check (
    auth.uid() = user_id
    and (
      not exists (
        select 1 from public.rooms r
        where r.id = room_presence.room_id and r.is_private = true
      )
      or exists (
        select 1 from public.room_members m
        where m.room_id = room_presence.room_id and m.user_id = auth.uid()
      )
    )
  );

-- ============================================================
-- RPC: create_private_room
-- ============================================================
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

  -- limit 2 room aktif per user
  select count(*) into active_count from public.rooms
   where owner_id = uid and is_private = true
     and (expires_at is null or expires_at > now());
  if active_count >= 2 then
    raise exception 'Room limit reached';
  end if;

  select points_enabled into points_on from public.app_settings where id = 'global';
  cost := case when has_pw then 150 else 100 end;

  if points_on is not false then
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

-- ============================================================
-- RPC: join_private_room
-- ============================================================
create or replace function public.join_private_room(
  p_room_id text,
  p_password text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  r record;
  points_on boolean;
  am_registered boolean;
  remaining int;
  charged int := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into r from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found';
  end if;

  -- room kedaluwarsa
  if r.is_private and r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;

  -- bukan private, atau owner, atau sudah member → gratis
  if not r.is_private or r.owner_id = uid
     or exists (select 1 from public.room_members m
                where m.room_id = p_room_id and m.user_id = uid) then
    insert into public.room_members (room_id, user_id) values (p_room_id, uid)
      on conflict do nothing;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0));
  end if;

  -- verifikasi password DULU (sebelum menyentuh koin)
  if r.has_password then
    if p_password is null or r.password_hash is null
       or crypt(p_password, r.password_hash) <> r.password_hash then
      raise exception 'Wrong password';
    end if;
  end if;

  select points_enabled into points_on from public.app_settings where id = 'global';

  if points_on is not false then
    select points into remaining from public.profiles where id = uid;
    if coalesce(remaining, 0) < 5 then
      raise exception 'Not enough points';
    end if;
    update public.profiles set points = points - 5 where id = uid
      returning points into remaining;
    charged := 5;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_join', -5);

    -- fee ke owner HANYA jika joiner terdaftar (anti-farming akun anonim)
    select is_registered into am_registered from public.profiles where id = uid;
    if am_registered is true and r.owner_id is not null and r.owner_id <> uid then
      update public.profiles set points = points + 5 where id = r.owner_id;
      insert into public.point_events (user_id, event, amount)
        values (r.owner_id, 'private_room_income', 5);
    end if;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  insert into public.room_members (room_id, user_id) values (p_room_id, uid)
    on conflict do nothing;

  return jsonb_build_object('ok', true, 'charged', charged, 'points', coalesce(remaining, 0));
end;
$$;

-- ============================================================
-- RPC: extend_private_room (owner, 50 koin, +7 hari)
-- ============================================================
create or replace function public.extend_private_room(p_room_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  r record;
  points_on boolean;
  remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;

  select points_enabled into points_on from public.app_settings where id = 'global';
  if points_on is not false then
    select points into remaining from public.profiles where id = uid;
    if coalesce(remaining, 0) < 50 then
      raise exception 'Not enough points';
    end if;
    update public.profiles set points = points - 50 where id = uid
      returning points into remaining;
    insert into public.point_events (user_id, event, amount)
      values (uid, 'private_room_extend', -50);
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  update public.rooms
    set expires_at = greatest(coalesce(expires_at, now()), now()) + interval '7 days'
    where id = p_room_id
    returning expires_at into r.expires_at;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
                            'expires_at', r.expires_at);
end;
$$;

-- ============================================================
-- RPC: delete_private_room (owner only, tanpa refund)
-- ============================================================
create or replace function public.delete_private_room(p_room_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r record;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then return; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;
  -- messages, room_members, room_presence ikut terhapus via FK cascade
  delete from public.rooms where id = p_room_id;
end;
$$;

-- ============================================================
-- RPC: cleanup_expired_rooms (dipanggil client saat buka lobby)
-- ============================================================
create or replace function public.cleanup_expired_rooms()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.rooms
   where is_private = true and expires_at is not null and expires_at <= now();
end;
$$;

-- ── Grants ──
revoke execute on function public.create_private_room(text, text, text, text) from public, anon;
grant execute on function public.create_private_room(text, text, text, text) to authenticated;
revoke execute on function public.join_private_room(text, text) from public, anon;
grant execute on function public.join_private_room(text, text) to authenticated;
revoke execute on function public.extend_private_room(text) from public, anon;
grant execute on function public.extend_private_room(text) to authenticated;
revoke execute on function public.delete_private_room(text) from public, anon;
grant execute on function public.delete_private_room(text) to authenticated;
grant execute on function public.cleanup_expired_rooms() to anon, authenticated;
