-- ============================================================
-- Fix: kandidat picker privasi ("kecuali..." & "Hanya orang tertentu")
-- tidak memuat user REGISTERED yang pernah 1:1 chat.
--
-- KELUHAN (user): memilih "Hanya orang tertentu" — "Kartika" (registered,
-- pernah chat) tidak muncul saat dicari. Akar: `privacy_excludable_users`
-- @20260929130000 hanya menambah chatters `is_registered = false` (anon),
-- sehingga user registered non-teman tak pernah jadi kandidat.
--
-- FIX: buang syarat `is_registered = false` → SEMUA yang pernah 1:1 chat
-- dengan saya jadi kandidat (registered + anon). Selebihnya sama persis
-- (teman | follower-ku | subscriber aktifku | sudah di daftar saya).
--
-- SUMBER: privacy_excludable_users @20260929130000_privacy_only_whitelist.sql.
-- CARA APPLY: Management API (CLI db push HANG).
-- ROLLBACK: re-apply definisi @20260929130000.
-- ============================================================

create or replace function public.privacy_excludable_users()
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'uid', x.id,
        'nickname', x.nickname,
        'avatar', x.avatar,
        'is_registered', x.is_registered,
        'is_friend', x.is_friend
      )
      order by x.is_friend desc, x.nickname
    ),
    '[]'::jsonb
  )
  from (
    select
      p.id,
      p.nickname,
      p.avatar,
      p.is_registered,
      public._privacy_are_friends(auth.uid(), p.id) as is_friend
    from public.profiles p
    where p.id <> auth.uid()
      and (
        -- teman (mutual follow)
        public._privacy_are_friends(auth.uid(), p.id)
        -- orang yang follow saya
        or exists (
          select 1 from public.follows f
          where f.follower_id = p.id and f.followee_id = auth.uid()
        )
        -- subscriber aktif saya
        or exists (
          select 1 from public.subscriptions s
          where s.subscriber_id = p.id and s.creator_id = auth.uid()
            and s.expires_at > now()
        )
        -- pernah 1:1 chat dengan saya (registered MAUPUN anon)
        or exists (
          select 1 from public.private_chats c
          where auth.uid() = any(c.participants)
            and p.id = any(c.participants)
        )
        -- sudah ada di daftar "hanya orang tertentu" saya (field apa pun)
        or exists (
          select 1 from public.profile_privacy_exclusions e
          where e.owner_id = auth.uid() and e.excluded_uid = p.id
        )
      )
    limit 500
  ) x;
$fn$;

revoke execute on function public.privacy_excludable_users() from public, anon;
grant execute on function public.privacy_excludable_users() to authenticated;
