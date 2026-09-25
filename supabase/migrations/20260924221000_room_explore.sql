-- menyentuh: create_private_room
-- Explore room ala gambar: chip kategori (Rame/Game/Musik/Curhat/...) + satu
-- list gabungan global + grup + buat room GRATIS dalam kategori + unread sync.
--
-- 1) create_private_room: tambah p_category (allowlist 10 kategori + 'private'
--    legacy). Kategori ASLI (bukan 'private') = GRATIS (skip ledger), terbuka
--    (approval_required=false, max_members=200). Legacy 'private' tidak berubah
--    (bayar + approval + max 20). Seluruh cabang lama dipertahankan dari
--    snapshot @20260905190000 (REGISTERED_ONLY, idempotency 10 dtk, limit 2).
-- 2) room_reads (BARU): last_read per user per room → unread sync antar-device.
-- 3) list_room_explore(p_country): satu list berisi member_count, online
--    (presence 10 mnt), pesan terakhir, is_live (HANYA grup: is_private AND
--    live_uid NOT NULL — global tidak pernah Live), unread vs room_reads.
-- 4) mark_room_read(p_room_id): upsert last_read = now().
-- Hapus overload 4-arg lama: Postgres menganggap beda signature (bukan replace),
-- PostgREST akan 300 Multiple Choices bila dua-duanya ada (insiden dummy_ai 2026-09-11).
drop function if exists public.create_private_room(text, text, text, text);
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

  -- Kategori: allowlist 10 kategori global + 'private' (legacy grup).
  v_cat := coalesce(nullif(btrim(coalesce(p_category, '')), ''), 'private');
  if v_cat not in ('general', 'curhat', 'pertemanan', 'teknologi', 'gaming',
                   'musik', 'film', 'joke', 'belajar', 'flirt', 'private') then
    raise exception 'Invalid category';
  end if;
  v_is_category := (v_cat <> 'private');

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
          true, uid, coalesce(my_name, 'Anon'),
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

-- 2) room_reads: last_read per user per room (unread sync antar-device).
create table if not exists public.room_reads (
  user_id uuid not null references public.profiles(id) on delete cascade,
  room_id text not null references public.rooms(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (user_id, room_id)
);
alter table public.room_reads enable row level security;
drop policy if exists room_reads_own on public.room_reads; -- SAFE: tabel baru room_reads milik migrasi ini sendiri, idempoten re-apply
create policy room_reads_own on public.room_reads for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id); -- SAFE: tabel baru, baris milik sendiri saja, tidak dipakai fitur lain

-- 3) Satu list explore: global + grup satu negara beserta statistik.
create or replace function public.list_room_explore(p_country text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
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
      and (r.expires_at is null or r.expires_at > now() or r.owner_id = auth.uid())
    order by o.cnt desc nulls last, lm.created_at desc nulls last
    limit 200
  ) t;
$fn$;
revoke execute on function public.list_room_explore(text) from public, anon; -- SAFE: RPC baca list room, pola sama seperti list_my_groups
grant execute on function public.list_room_explore(text) to authenticated; -- SAFE: RPC baca list room untuk user login saja

-- 4) Tandai room sudah dibaca (sinkron antar-device).
create or replace function public.mark_room_read(p_room_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  insert into public.room_reads(user_id, room_id, last_read_at)
  values (uid, p_room_id, now())
  on conflict (user_id, room_id) do update set last_read_at = now();
  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function public.mark_room_read(text) from public, anon; -- SAFE: RPC tulis last_read milik sendiri saja
grant execute on function public.mark_room_read(text) to authenticated; -- SAFE: RPC tulis last_read milik sendiri saja
