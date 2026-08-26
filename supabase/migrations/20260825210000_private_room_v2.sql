-- ============================================================
-- Private Room v2 — scale & moderation
-- - Role-based membership (owner/admin/member)
-- - Join approval queue + riwayat permanen
-- - Live broadcast state (1 broadcaster aktif)
-- - Signaling table (ephemeral) untuk WebRTC mesh
-- - Kapasitas atomik (row lock) aman untuk konkurensi tinggi
-- ============================================================

-- ---------- 1) Skema dasar ----------
alter table public.room_members
  add column if not exists role text not null default 'member'
    check (role in ('owner','admin','member'));

alter table public.rooms
  add column if not exists join_token text,
  add column if not exists live_uid uuid,
  add column if not exists live_started_at timestamptz,
  add column if not exists max_members int not null default 20,
  add column if not exists approval_required boolean not null default true;

-- Backfill: owner jadi role owner; private room lama dapat token.
update public.room_members m
   set role = 'owner'
  from public.rooms r
 where r.id = m.room_id and r.owner_id = m.user_id and m.role = 'member';

update public.rooms
   set join_token = substr(replace(gen_random_uuid()::text, '-', ''), 1, 22)
 where is_private = true and join_token is null;

create index if not exists rooms_live_idx
  on public.rooms (live_uid) where live_uid is not null;
create index if not exists rooms_token_idx
  on public.rooms (join_token) where is_private = true;

-- ---------- 2) Antrean approval ----------
create table if not exists public.room_join_requests (
  id            uuid primary key default gen_random_uuid(),
  room_id       text not null references public.rooms(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  nickname      text not null default '',
  status        text not null default 'pending'
                check (status in ('pending','approved','rejected','kicked')),
  requested_at  timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid
);

-- Satu baris per (room, user) → upsert status; riwayat terakhir menang.
create unique index if not exists rjr_room_user_uniq
  on public.room_join_requests (room_id, user_id);
-- Query antrean admin: hanya pending, terbaru dulu.
create index if not exists rjr_pending_idx
  on public.room_join_requests (room_id, requested_at desc)
  where status = 'pending';

alter table public.room_join_requests enable row level security;
drop policy if exists rjr_select_own on public.room_join_requests;
create policy rjr_select_own on public.room_join_requests
  for select using (user_id = auth.uid());
drop policy if exists rjr_insert_own on public.room_join_requests;
create policy rjr_insert_own on public.room_join_requests
  for insert with check (user_id = auth.uid());

-- ---------- 3) Signaling broadcast (ephemeral, volume tinggi) ----------
create table if not exists public.room_signals (
  id         bigint generated always as identity primary key,
  room_id    text not null,
  from_uid   uuid not null,
  to_uid     uuid,                       -- null = broadcast ke semua
  type       text not null,              -- b_offer|b_answer|b_cand|b_bye
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Hanya index minimum: tabel ini churn tinggi & di-purge berkala.
create index if not exists room_signals_fetch_idx
  on public.room_signals (room_id, id);

alter table public.room_signals enable row level security;
drop policy if exists rs_insert_member on public.room_signals;
create policy rs_insert_member on public.room_signals
  for insert with check (
    from_uid = auth.uid()
    and exists (
      select 1 from public.room_members m
       where m.room_id = room_signals.room_id
         and m.user_id = auth.uid()
    )
  );
drop policy if exists rs_select_member on public.room_signals;
create policy rs_select_member on public.room_signals
  for select using (
    exists (
      select 1 from public.room_members m
       where m.room_id = room_signals.room_id
         and m.user_id = auth.uid()
    )
  );

-- Realtime: kirim event ke client (member sudah difilter RLS).
alter publication supabase_realtime add table public.room_signals;
alter publication supabase_realtime add table public.room_members;
alter publication supabase_realtime add table public.room_join_requests;

-- ---------- 4) Helper role ----------
create or replace function public.fn_room_role(p_uid uuid, p_room_id text)
returns text
language sql stable security definer
set search_path to 'public'
as $fn$
  select role from public.room_members
   where user_id = p_uid and room_id = p_room_id
   limit 1;
$fn$;

-- ---------- 5) Patch create_private_room ----------
-- (body asli dipertahankan; tambahan: join_token, max_members,
--  approval_required, dan creator otomatis role owner)

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
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then raise exception 'Invalid room name'; end if;
  if p_country is null or p_country = '' then raise exception 'Invalid country'; end if;

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

-- ---------- 6) join_private_room: kapasitas atomik + approval ----------
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

  -- Lock baris room → cek kapasitas anti-race saat banyak join bersamaan.
  select * into r_lock from public.rooms where id = p_room_id for update;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.is_private and r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired'; end if;

  -- Sudah member / owner → pastikan ada & selesai.
  if r.owner_id = uid
     or exists (select 1 from public.room_members m
                where m.room_id = p_room_id and m.user_id = uid) then
    insert into public.room_members (room_id, user_id, role)
    values (p_room_id, uid, case when r.owner_id = uid then 'owner' else 'member' end)
    on conflict (room_id, user_id) do update set role = excluded.role;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
  end if;

  -- Kapasitas: hitung member aktif vs max_members (terkunci di atas).
  select count(*) into member_count from public.room_members where room_id = p_room_id;
  if member_count >= r.max_members then
    raise exception 'Room full';
  end if;

  if not r.is_private then
    insert into public.room_members (room_id, user_id, role) values (p_room_id, uid, 'member')
      on conflict do nothing;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
  end if;

  if r.has_password then
    if p_password is null or r.password_hash is null
       or crypt(p_password, r.password_hash) <> r.password_hash then
      raise exception 'Wrong password'; end if;
  end if;

  -- Mode approval: masuk antrean, TIDAK langsung jadi member.
  if r.approval_required then
    insert into public.room_join_requests (room_id, user_id)
    values (p_room_id, uid)
    on conflict (room_id, user_id) do update
      set status = 'pending', requested_at = now(), decided_at = null, decided_by = null;
    return jsonb_build_object('ok', true, 'pending', true, 'charged', 0);
  end if;

  -- Jalur auto-join lama (approval_required = false): tetap kenakan poin.
  select points_enabled, room_join_paid, bonus_price_multiplier
    into points_on, paid, mult from app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'join');
    tier := res->>'tier';
    remaining := (res->>'remaining')::int;
    charged := case when tier = 'paid' then paid else bonus_p end;

    select is_registered into am_registered from public.profiles where id = uid;
    if am_registered is true and r.owner_id is not null and r.owner_id <> uid then
      perform public.ledger_credit(r.owner_id,
        case when tier = 'paid' then 'earned' else 'bonus' end,
        'private_room_income', charged, p_room_id,
        jsonb_build_object('joiner', uid, 'tier', tier));
      insert into public.point_events (user_id, event, amount)
        values (r.owner_id, 'private_room_income', charged);
    end if;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  insert into public.room_members (room_id, user_id, role) values (p_room_id, uid, 'member')
    on conflict do nothing;
  insert into public.room_join_requests (room_id, user_id, status, decided_at)
  values (p_room_id, uid, 'approved', now())
  on conflict (room_id, user_id) do update set status='approved', decided_at=now();
  return jsonb_build_object('ok', true, 'charged', charged, 'points', coalesce(remaining, 0), 'pending', false);
end; $function$;

-- ---------- 7) Moderasi: approve/reject/kick/role/leave ----------
create or replace function public.approve_join_request(p_room_id text, p_uid uuid)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $fn$
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
$fn$;

create or replace function public.reject_join_request(p_room_id text, p_uid uuid)
returns void
language plpgsql security definer
set search_path to 'public'
as $fn$
declare actor_role text;
begin
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role not in ('owner','admin') then raise exception 'Forbidden'; end if;
  update public.room_join_requests
     set status='rejected', decided_at=now(), decided_by=auth.uid()
   where room_id = p_room_id and user_id = p_uid;
end;
$fn$;

create or replace function public.kick_room_member(p_room_id text, p_uid uuid)
returns void
language plpgsql security definer
set search_path to 'public'
as $fn$
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
$fn$;

create or replace function public.set_member_role(p_room_id text, p_uid uuid, p_role text)
returns void
language plpgsql security definer
set search_path to 'public'
as $fn$
declare actor_role text; target_role text; owner uuid;
begin
  if p_role not in ('admin','member') then raise exception 'Invalid role'; end if;
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role is distinct from 'owner' then raise exception 'Only owner can change roles'; end if;

  select role into target_role from public.room_members
   where room_id = p_room_id and user_id = p_uid;
  if target_role is null or target_role = 'owner' or p_uid = auth.uid() then
    raise exception 'Forbidden'; end if;

  update public.room_members set role = p_role
   where room_id = p_room_id and user_id = p_uid;
end;
$fn$;

-- Leave: owner leave → transfer otomatis ke admin/member tertua.
create or replace function public.leave_private_room(p_room_id text)
returns void
language plpgsql security definer
set search_path to 'public'
as $fn$
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
$fn$;

-- ---------- 8) Broadcast grant/stop ----------
create or replace function public.grant_broadcast(p_room_id text, p_uid uuid)
returns void
language plpgsql security definer
set search_path to 'public'
as $fn$
declare actor_role text;
begin
  actor_role := public.fn_room_role(auth.uid(), p_room_id);
  if actor_role not in ('owner','admin') then raise exception 'Forbidden'; end if;
  if public.fn_room_role(p_uid, p_room_id) is null then
    raise exception 'Target not a member'; end if;
  update public.rooms
     set live_uid = p_uid, live_started_at = now()
   where id = p_room_id;
end;
$fn$;

create or replace function public.stop_broadcast(p_room_id text)
returns void
language plpgsql security definer
set search_path to 'public'
as $fn$
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
$fn$;

-- ---------- 9) Query list untuk UI ----------
create or replace function public.list_room_join_requests(p_room_id text)
returns jsonb
language sql stable security definer
set search_path to 'public'
as $fn$
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
$fn$;

create or replace function public.list_room_members_v2(p_room_id text)
returns jsonb
language sql stable security definer
set search_path to 'public'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', m.user_id, 'nickname', coalesce(pr.nickname,'User'),
           'role', m.role, 'joined_at', m.joined_at,
           'status', pr.status, 'last_seen', pr.last_seen
         ) order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,
                    pr.nickname), '[]'::jsonb)
    from public.room_members m
    left join public.profiles pr on pr.id = m.user_id
   where m.room_id = p_room_id;
$fn$;

revoke execute on function public.approve_join_request(text,uuid),
  public.reject_join_request(text,uuid), public.kick_room_member(text,uuid),
  public.set_member_role(text,uuid,text), public.grant_broadcast(text,uuid),
  public.stop_broadcast(text), public.list_room_join_requests(text),
  public.list_room_members_v2(text), public.leave_private_room(text)
  from public, anon;
grant execute on function public.leave_private_room(text), public.stop_broadcast(text) to authenticated;

-- Semua aksi moderasi/anggota dipanggil oleh authenticated user;
-- keamanannya dijaga guard role di dalam body masing-masing fungsi.
grant execute on function
  public.approve_join_request(text,uuid),
  public.reject_join_request(text,uuid),
  public.kick_room_member(text,uuid),
  public.set_member_role(text,uuid,text),
  public.grant_broadcast(text,uuid),
  public.list_room_join_requests(text),
  public.list_room_members_v2(text)
  to authenticated;

-- ---------- 10) Purge otomatis (pg_cron) ----------
-- Signals >2 jam dibuang (ephemeral); join request decided >90 hari diarsip-dibuang.
select cron.schedule('purge_room_signals', '15 * * * *',
  $$delete from public.room_signals where created_at < now() - interval '2 hours'$$);

select cron.schedule('purge_old_join_requests', '20 3 * * *',
  $$delete from public.room_join_requests where status in ('approved','rejected') and decided_at < now() - interval '90 days'$$);
