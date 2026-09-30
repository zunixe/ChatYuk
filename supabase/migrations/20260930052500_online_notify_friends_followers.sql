-- ============================================================
-- Notif "X online" → teman + follower + pernah 1:1 chat.
--
-- MINTA USER: saat A online, notifikasinya ke teman, follower, dan orang
-- di list chat yang pernah chat dengan dia (dulu HANYA yang pernah chat).
--
-- ISI: rewrite penerima notify_contact_online = UNION:
--   teman (mutual follow) | follower-ku | pernah 1:1 chat (lama).
--   chatId diisi bila ada chat 1:1 (tap → buka chat), else NULL
--   (klien: tap → buka profil). Skip blokir dua arah (dulu tak dicek —
--   selaras get_online_users). Guard lain utuh (hanya transisi
--   →online; author dummy tak notify).
--
-- SUMBER: notify_contact_online live (trigger
--   notify_contact_online_trigger AFTER UPDATE OF status).
-- CARA APPLY: Management API (CLI db push HANG).
-- ROLLBACK: re-apply definisi lama (hanya chatters).
-- ============================================================

create or replace function public.notify_contact_online()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  contact_id uuid;
  contact_chat text;
  t text;
begin
  if new.status <> 'online' or old.status = 'online' then return new; end if;
  -- Dummy: bot tidak perlu memberi tahu kontak bahwa ia "online".
  if exists (select 1 from public.dummy_accounts d where d.uid = new.id) then
    return new;
  end if;
  for contact_id, contact_chat in
    select distinct u.uid, (
      select pc.chat_id from public.private_chats pc
      where new.id = any (pc.participants)
        and u.uid = any (pc.participants)
      limit 1
    )
    from (
      -- teman (mutual follow)
      select f1.followee_id as uid
      from public.follows f1
      join public.follows f2
        on f1.followee_id = f2.follower_id
       and f1.follower_id = f2.followee_id
      where f1.follower_id = new.id
      union
      -- follower-ku
      select f.follower_id as uid
      from public.follows f
      where f.followee_id = new.id
      union
      -- pernah 1:1 chat (perilaku lama)
      select distinct u as uid
      from public.private_chats pc
      cross join lateral unnest(pc.participants) as u
      where new.id = any (pc.participants) and u <> new.id
    ) u
    where u.uid <> new.id
      -- skip blokir dua arah (selaras get_online_users)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = u.uid and b.blocked_id = new.id)
           or (b.blocker_id = new.id and b.blocked_id = u.uid)
      )
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
end;
$fn$;
