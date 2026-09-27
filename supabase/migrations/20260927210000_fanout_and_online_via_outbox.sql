-- ============================================================
-- Outbox Fase E: fanout topical + contact_online + broadcast → OUTBOX
--
-- Mengganti `perform net.http_post(...)` (SINKRON, jalur trigger) →
-- `insert into public.outbox`. Dikirim oleh edge outbox-worker (v2 yang
-- sudah mendukung endpoint 'fanout' & 'send-push').
--
-- Fungsi yang diubah (TIDAK ada di frozen_functions.txt):
--   - notify_online_fanout        → outbox (endpoint fanout, {type:online,id})
--   - notify_room_fanout          → outbox (endpoint fanout, {type:room,id})
--   - notify_timeline_post_fanout → outbox (endpoint fanout, {type:timeline,id})
--   - notify_timeline_count_fanout→ outbox (endpoint fanout, {type:timeline,id})
--   - notify_contact_online       → outbox (endpoint send-push)
--   - notify_broadcast_started    → outbox (endpoint send-push)
--
-- Logika lain 100% IDENTIK (guard debounce 10 mnt / 5 dtk, update
-- last_*_notified_at, token via user_fcm_tokens). Dasar = definisi LIVE.
--
-- PENTING: worker outbox-worker v2 + cron chatyuk-outbox-worker WAJIB aktif.
-- ROLLBACK: re-apply definisi lama (lihat MIGRATION_LOG 2026-09-27).
-- ============================================================

-- ── notify_online_fanout ────────────────────────────────────────────────────
create or replace function public.notify_online_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status = 'online' and coalesce(old.status,'offline') != 'online' then
    if new.last_online_notified_at is null or now() - new.last_online_notified_at > interval '10 minutes' then
      insert into public.outbox (type, payload)
      values ('fanout', jsonb_build_object('endpoint','fanout','type','online','id', new.id::text));
      update public.profiles set last_online_notified_at = now() where id = new.id;
    end if;
  end if;
  return new;
end; $function$;

-- ── notify_room_fanout ──────────────────────────────────────────────────────
create or replace function public.notify_room_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.outbox (type, payload)
  values ('fanout', jsonb_build_object('endpoint','fanout','type','room','id', new.id::text));
  return new;
end; $function$;

-- ── notify_timeline_post_fanout ─────────────────────────────────────────────
create or replace function public.notify_timeline_post_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.outbox (type, payload)
  values ('fanout', jsonb_build_object('endpoint','fanout','type','timeline','id', new.id::text));
  return new;
end; $function$;

-- ── notify_timeline_count_fanout ────────────────────────────────────────────
create or replace function public.notify_timeline_count_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if coalesce(new.like_count,0) = coalesce(old.like_count,0)
     and coalesce(new.comment_count,0) = coalesce(old.comment_count,0)
     and coalesce(new.share_count,0) = coalesce(old.share_count,0) then
    return new;
  end if;
  if new.last_notified_at is null or now() - new.last_notified_at > interval '5 seconds' then
    insert into public.outbox (type, payload)
    values ('fanout', jsonb_build_object('endpoint','fanout','type','timeline','id', new.id::text));
    update public.posts set last_notified_at = now() where id = new.id;
  end if;
  return new;
end; $function$;

-- ── notify_contact_online ───────────────────────────────────────────────────
create or replace function public.notify_contact_online()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  contact_id uuid;
  contact_chat text;
  t text;
begin
  if new.status <> 'online' or old.status = 'online' then return new; end if;
  for contact_id, contact_chat in
    select distinct u as uid, pc.chat_id
      from public.private_chats pc
      cross join lateral unnest(pc.participants) as u
     where new.id = any (pc.participants) and u <> new.id
  loop
    for t in select public.user_fcm_tokens(contact_id) loop
      insert into public.outbox (type, payload)
      values ('push', jsonb_build_object(
        'endpoint','send-push',
        'token', t,
        'title', coalesce(new.nickname,'Anon'),
        'body', 'is online',
        'data', jsonb_build_object(
          'type','online','chatId',contact_chat,
          'otherUid',new.id,'otherName',coalesce(new.nickname,'Anon')
        )
      ));
    end loop;
  end loop;
  return new;
exception when others then return new;
end; $function$;

-- ── notify_broadcast_started ────────────────────────────────────────────────
create or replace function public.notify_broadcast_started()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
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
end; $function$;

-- Verifikasi:
--   select proname, (prosrc like '%outbox%') ob, (prosrc like '%http_post%') hp
--     from pg_proc where proname in
--     ('notify_online_fanout','notify_room_fanout','notify_timeline_post_fanout',
--      'notify_timeline_count_fanout','notify_contact_online','notify_broadcast_started');
--   → semua ob=true, hp=false.
