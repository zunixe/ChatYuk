-- ============================================================
-- STORY: admin ghost-mode — lihat story orang tanpa tercatat.
--
-- LATAR: admin (zunixe@gmail.com) memakai viewer yang sama dengan user.
-- Setiap slide yang dibuka memanggil mark_story_seen_bulk → baris
-- story_views (viewer_id = admin) tercatat → pemilik story MELIHAT nama
-- admin di daftar penonton. Tidak diinginkan: admin memoderasi story
-- harus invisible.
--
-- PERBAIKAN (3 lapis, defense-in-depth):
--   1) mark_story_seen (single): return ok tanpa insert bila pemanggil
--      admin (is_admin_request) dan bukan author sendiri.
--   2) mark_story_seen_bulk: WHERE ditambah
--      `(s.author_id = uid or not is_admin_request())` → bulk admin hanya
--      mencatat story milik sendiri, story orang lain dilewati.
--   3) story_viewers: hasil disaring — baris viewer admin TIDAK pernah
--      dikembalikan (walau lolos via client lama), + CLEANUP di bawah
--      menghapus baris admin yang SUDAH tercatat ("hapus yang udah keliatan").
--
-- Client (story_viewer_screen.dart) juga skip _markSeen/_flushSeen untuk
-- admin → 0 RPC. Guard server ini jaring pengaman bila client lama/bypass.
--
-- Signature RPC TIDAK berubah. Fungsi yang disentuh BUKAN FROZEN
-- (frozen: story_slides, create_story — tidak disentuh di sini).
-- Grants tidak berubah (revoke execute rutin dikecualikan guard).
--
-- CARA APPLY: Management API (CLI db push HANG di Mac ini).
-- ============================================================

-- ── 1. mark_story_seen: ghost admin ──
create or replace function public.mark_story_seen(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  uid uuid := auth.uid();
  v_author uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  select s.author_id into v_author
  from public.stories s
  where s.id = p_story_id;
  -- Ghost-mode: admin lihat story orang → akui ok TANPA mencatat.
  -- Story milik sendiri tetap dicatat (konsisten dengan bulk).
  if v_author is not null and v_author <> uid and public.is_admin_request() then
    return jsonb_build_object('ok', true);
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

-- ── 2. mark_story_seen_bulk: ghost admin ──
create or replace function public.mark_story_seen_bulk(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  uid uuid := auth.uid();
  n integer := 0;
  v_is_admin boolean := public.is_admin_request();
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_ids is null or array_length(p_ids, 1) is null then return 0; end if;

  insert into public.story_views (story_id, viewer_id)
  select s.id, uid
  from public.stories s
  where s.id = any (p_ids)
    and s.expires_at > now()
    -- Ghost-mode: admin hanya mencatat story milik sendiri.
    and (s.author_id = uid or not v_is_admin)
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

-- ── 3. story_viewers: jangan kembalikan baris admin ──
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
  where v.story_id = p_story_id
    -- Ghost-mode: baris admin tidak pernah tampil di daftar penonton,
    -- walau lolos tercatat via client lama/bypass.
    and not exists (
      select 1 from auth.users u
      where u.id = v.viewer_id
        and lower(coalesce(u.email, '')) = 'zunixe@gmail.com'
    );
  return result;
end;
$fn$;

revoke execute on function public.story_viewers(uuid) from public, anon;
grant execute on function public.story_viewers(uuid) to authenticated;

-- ── 4. CLEANUP: hapus jejak admin yang SUDAH tercatat ──
-- ("hapus yang udah keliatan" — pemilik story tidak lagi melihat admin.)
delete from public.story_views v
using auth.users u
where v.viewer_id = u.id
  and lower(coalesce(u.email, '')) = 'zunixe@gmail.com';
