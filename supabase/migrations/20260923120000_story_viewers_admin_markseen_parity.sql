-- ============================================================
-- STORY: penonton — admin bebas + pariti visibility mark_seen.
--
-- LATAR (audit 2026-09-23, versi live diverifikasi via Management API):
--   1) `story_viewers` HANYA mengizinkan author (`s.author_id = auth.uid()`),
--      padahal UI (story_viewer_screen.dart) menampilkan tombol penonton
--      untuk `_own || _isAdmin`. Admin membuka slide dummy → RPC
--      melempar 'Unauthorized' → client dulu menelan error jadi [] →
--      admin melihat "Belum ada penonton" (salah, menyesatkan).
--   2) `mark_story_seen` (single) mendukung 'everyone'/'registered'/'friends'
--      TANPA 'followers' dan TANPA cek blokir.
--   3) `mark_story_seen_bulk` mendukung 'everyone'/'followers'/'friends'
--      TANPA 'registered', sudah ada cek blokir.
--   Keduanya juga belum memanggil privacy_can_view(author,'story') yang
--   sudah jadi sumber kebenaran di `story_slides` + `story_tray`.
--   Akibatnya penonton tidak tercatat untuk sebagian kombinasi visibility
--   (daftar penonton jadi kurang), padahal slide-nya benar-benar dilihat.
--
-- PERBAIKAN:
--   - `story_viewers`: guard jadi author ATAU `is_admin_request()`.
--   - `mark_story_seen` + `mark_story_seen_bulk`: daftar visibility
--     DISAMAKAN ke 'everyone'/'followers'/'friends'/'registered' +
--     cek blokir dua arah + `privacy_can_view(author,'story')`.
--
-- Signature RPC TIDAK berubah (tanpa DROP FUNCTION). Fungsi FROZEN tidak
-- disentuh (`story_viewers`/`mark_story_seen*` bukan anggota
-- scripts/frozen_functions.txt — lihat snapshot: hanya `story_slides` &
-- `create_story` yang FROZEN).
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

-- ── 1. story_viewers: admin bebas, penonton tetap real ─────────
create or replace function public.story_viewers(p_story_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  -- Pemilik slide ATAU admin (guard admin anti-rentan: cek email di DB,
  -- bukan hanya klaim JWT — pola is_admin_request()).
  if not exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and (s.author_id = auth.uid() or public.is_admin_request())
  ) then
    raise exception 'Unauthorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'viewer_id', v.viewer_id,
    'nickname', pr.nickname,
    'avatar', pr.avatar,
    'viewed_at', v.viewed_at,
    'liked', exists (
      select 1 from public.story_likes l
      where l.story_id = p_story_id and l.user_id = v.viewer_id)
  ) order by v.viewed_at desc), '[]'::jsonb)
  into result
  from public.story_views v
  join public.profiles pr on pr.id = v.viewer_id
  where v.story_id = p_story_id;
  return result;
end;
$fn$;

revoke execute on function public.story_viewers(uuid) from public, anon;
grant execute on function public.story_viewers(uuid) to authenticated;

-- ── 2. mark_story_seen: pariti visibility + blokir + privacy ───
create or replace function public.mark_story_seen(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and s.expires_at > now()
      and public.privacy_can_view(s.author_id, 'story', uid)
      and (
        s.author_id = uid
        or (
          (
            (s.visibility = 'everyone')
            or (s.visibility = 'followers' and exists (
                  select 1 from public.follows f
                  where f.follower_id = uid and f.followee_id = s.author_id))
            or (s.visibility = 'friends' and public._are_friends(uid, s.author_id))
            or (s.visibility = 'registered' and public._viewer_is_registered())
          )
          and not exists (
            select 1 from public.blocks b
            where (b.blocker_id = uid and b.blocked_id = s.author_id)
               or (b.blocker_id = s.author_id and b.blocked_id = uid)
          )
        )
      )
  ) then
    insert into public.story_views (story_id, viewer_id)
    values (p_story_id, uid)
    on conflict (story_id, viewer_id) do nothing;
  end if;
  return jsonb_build_object('ok', true);
end;
$fn$;

revoke execute on function public.mark_story_seen(uuid) from public, anon;
grant execute on function public.mark_story_seen(uuid) to authenticated;

-- ── 3. mark_story_seen_bulk: + 'registered' + privacy ──────────
create or replace function public.mark_story_seen_bulk(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  uid uuid := auth.uid();
  n integer := 0;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_ids is null or array_length(p_ids, 1) is null then return 0; end if;

  insert into public.story_views (story_id, viewer_id)
  select s.id, uid
  from public.stories s
  where s.id = any (p_ids)
    and s.expires_at > now()
    -- Privacy story author (sumber kebenaran sama dengan story_slides/tray).
    and public.privacy_can_view(s.author_id, 'story', uid)
    and (
      s.author_id = uid
      or (
        (
          (s.visibility = 'everyone')
          or (s.visibility = 'followers' and exists (
                select 1 from public.follows f
                where f.follower_id = uid and f.followee_id = s.author_id))
          or (s.visibility = 'friends' and public._are_friends(uid, s.author_id))
          -- DITAMBAH: slide 'registered' dulu tak pernah tercatat di bulk
          -- (hanya ada di jalur single) → penonton hilang dari daftar.
          or (s.visibility = 'registered' and public._viewer_is_registered())
        )
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = uid and b.blocked_id = s.author_id)
             or (b.blocker_id = s.author_id and b.blocked_id = uid)
        )
      )
    )
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$fn$;

revoke execute on function public.mark_story_seen_bulk(uuid[]) from public, anon;
grant execute on function public.mark_story_seen_bulk(uuid[]) to authenticated;
