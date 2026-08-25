-- Arsip user terhapus + pelestarian riwayat device/lokasi saat user dihapus.

-- 1. Tabel arsip permanen (audit). Hanya admin yang boleh lihat/tulis.
create table if not exists public.deleted_users (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null,           -- uid asli (tetap disimpan)
  nickname       text not null default '',
  email          text,
  is_registered  boolean not null default false,
  brand          text not null default '',
  model          text not null default '',
  ip_address     text not null default '',
  last_seen_at   timestamptz,
  created_at     timestamptz,
  deleted_at     timestamptz not null default now(),
  reason         text not null default 'unknown', -- stale_cleanup|nickname_claim|admin_delete|dummy_delete
  claimed_by     uuid,                             -- untuk nickname_claim: uid yang mengambil
  claimed_nick   text,                             -- nickname baru si pengambil (jika beda)
  unique (user_id)
);

create index if not exists deleted_users_deleted_idx on public.deleted_users (deleted_at desc);
create index if not exists deleted_users_reason_idx on public.deleted_users (reason);

alter table public.deleted_users enable row level security;
drop policy if exists deleted_users_admin on public.deleted_users;
create policy deleted_users_admin on public.deleted_users
  for all
  using (coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com')
  with check (coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com');

-- 2. FK user_devices & user_location_history -> SET NULL (device = milik hardware,
--    jangan ikut terhapus saat user dihapus). Tambah snapshot nickname.
alter table public.user_devices drop constraint if exists user_devices_user_id_fkey;
alter table public.user_devices
  add constraint user_devices_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;

alter table public.user_devices add column if not exists nickname_snapshot text;

alter table public.user_location_history drop constraint if exists user_location_history_user_id_fkey;
alter table public.user_location_history
  add constraint user_location_history_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;

-- 3. Helper arsipkan user sebelum hard delete. Idempoten (unique user_id).
create or replace function public.fn_archive_deleted_user(
  p_uid uuid,
  p_reason text,
  p_claimed_by uuid default null,
  p_claimed_nick text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_nick text; v_email text; v_reg boolean; v_ip text;
  v_brand text; v_model text; v_last timestamptz; v_created timestamptz;
begin
  select nickname, email, coalesce(is_registered,false), ip_address,
         last_seen, created_at
    into v_nick, v_email, v_reg, v_ip, v_last, v_created
    from profiles where id = p_uid;

  -- Snapshot device terakhir milik user (sebelum user_devices di-SET NULL).
  select brand, model into v_brand, v_model
    from user_devices
   where user_id = p_uid
   order by last_seen_at desc nulls last
   limit 1;

  insert into public.deleted_users
    (user_id, nickname, email, is_registered, brand, model, ip_address,
     last_seen_at, created_at, deleted_at, reason, claimed_by, claimed_nick)
  values
    (p_uid, coalesce(v_nick,''), v_email, v_reg, coalesce(v_brand,''),
     coalesce(v_model,''), coalesce(v_ip,''), v_last, v_created, now(),
     p_reason, p_claimed_by, p_claimed_nick)
  on conflict (user_id) do nothing;
end;
$fn$;
-- 4. Ubah cleanup_stale_anonymous: arsipkan dulu sebelum hapus.
create or replace function public.cleanup_stale_anonymous(min_age_days integer DEFAULT 7)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  deleted int := 0;
  r record;
begin
  for r in
    select u.id
    from auth.users u
    where u.is_anonymous = true
      and u.email is null
      and not exists (
        select 1 from public.dummy_accounts d where d.uid = u.id
      )
      and not exists (
        select 1 from public.profiles p
        where p.id = u.id
          and p.last_seen > now() - make_interval(days => min_age_days)
      )
  loop
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

    delete from public.profiles where id = r.id;
    delete from auth.users where id = r.id;
    deleted := deleted + 1;
  end loop;
  return deleted;
end;
$function$;

-- 5. Ubah claim_nickname: arsipkan anon yang nicknamenya diambil.
create or replace function public.claim_nickname(p_nickname text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_owner uuid;
  v_registered boolean;
  v_last_seen timestamptz;
  v_new_nick text;
begin
  select id, coalesce(is_registered, false), coalesce(last_seen, created_at)
    into v_owner, v_registered, v_last_seen
    from profiles
   where nickname = p_nickname
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
$function$;

-- 6. Ubah admin_delete_dummy: arsipkan dulu.
create or replace function public.admin_delete_dummy(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_chats int;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  perform public.fn_archive_deleted_user(p_uid, 'dummy_delete');

  delete from public.private_chats where p_uid = any (participants);
  get diagnostics v_chats = row_count;

  delete from public.room_presence where user_id = p_uid;
  delete from public.user_photos where user_id = p_uid;

  alter table public.coin_ledger disable trigger coin_ledger_no_delete;
  delete from public.coin_ledger where user_id = p_uid;
  alter table public.coin_ledger enable trigger coin_ledger_no_delete;

  delete from public.dummy_accounts where uid = p_uid;
  delete from auth.users where id = p_uid;

  return jsonb_build_object('ok', true, 'chats_deleted', v_chats);
end;
$function$;

-- 7. Ubah admin_delete_chat: arsipkan user yang dihapus.
create or replace function public.admin_delete_chat(p_chat_id text, p_delete_user_ids uuid[] DEFAULT '{}'::uuid[])
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  admin_email text := coalesce(auth.email(),'');
  photo_paths jsonb := '[]'::jsonb;
  v_uid uuid;
begin
  if admin_email != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(image_data), '[]'::jsonb) into photo_paths
  from private_messages
  where chat_id = p_chat_id
    and image_data like 'chat/%';

  delete from public.private_messages where chat_id = p_chat_id;
  delete from public.private_chats where chat_id = p_chat_id;

  if array_length(p_delete_user_ids, 1) is not null then
    set local session_replication_role = 'replica';

    foreach v_uid in array p_delete_user_ids loop
      if exists (
        select 1 from auth.users where id = v_uid and email = 'zunixe@gmail.com'
      ) then
        continue;
      end if;
      perform public.fn_archive_deleted_user(v_uid, 'admin_delete');
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
$function$;

-- 8. RPC admin: list arsip user terhapus.
create or replace function public.admin_list_deleted(p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'total', (select count(*) from public.deleted_users),
    'items', coalesce(jsonb_agg(
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
        'claimed_nick', d.claimed_nick
      ) order by d.deleted_at desc
    ), '[]'::jsonb)
  ) into result
  from public.deleted_users d
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
  return result;
end;
$function$;

-- 9. RPC admin: riwayat device user yang dihapus (user_devices dgn user_id NULL
--    yang cocok dengan nickname_snapshot = nickname arsip).
create or replace function public.admin_deleted_device_history(p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
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
$function$;

revoke execute on function public.admin_list_deleted(integer,integer) from public, anon;
revoke execute on function public.admin_deleted_device_history(text) from public, anon;
