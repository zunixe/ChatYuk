-- ============================================================
-- RPC daftar teman untuk picker privasi "Teman kecuali".
--
-- Alasan: enforcement privacy memakai `_are_friends()` (friend_requests
-- accepted), sedangkan picker sebelumnya memakai `social_list('friends')`
-- yang berbasis mutual-follow. Dua definisi itu bisa berbeda (dua orang
-- saling follow tanpa pernah menerima friend request) → teman yang
-- muncul di picker belum tentu benar-benar masuk aturan privacy.
--
-- Solusi: satu RPC yang memakai definisi PERSIS sama dengan enforcement
-- (`_are_friends`), jadi pilihan pengecualian selalu valid.
-- ============================================================

create or replace function public.privacy_friends()
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'uid', p.id,
        'nickname', p.nickname,
        'avatar', p.avatar,
        'gender', p.gender,
        'is_registered', p.is_registered
      )
      order by p.nickname
    ),
    '[]'::jsonb
  )
  from public.profiles p
  where p.id <> auth.uid()
    and public._are_friends(auth.uid(), p.id);
$fn$;

revoke execute on function public.privacy_friends() from public, anon;
grant execute on function public.privacy_friends() to authenticated;
