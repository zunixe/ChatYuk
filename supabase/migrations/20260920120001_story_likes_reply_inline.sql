-- menyentuh: story_slides
-- ============================================================
-- STORY: kompat balas + tombol like/share di viewer.
--
-- Konteks (klien): viewer story orang lain kini menaruh foto SEUKURAN
-- pembuat story (kotak yang bisa digeser ke atas/bawah, bukannya terkunci
-- penuh layar) dan kolom balas berada DI DALAM foto. Tombol baru:
--   - LIKE  : disimpan server (jumlah like terlihat pembuat story)
--   - SHARE : share sheet HP (teks/tautan) — tidak butuh server
--
-- Perubahan server:
--   1) Tabel `story_likes` (PK story_id+user_id) + RLS.
--   2) RPC `toggle_story_like(p_story_id)` — idempoten per tap, guard
--      visibilitas/blokir sama seperti mark_story_seen, kembalikan
--      {ok, liked, count}.
--   3) RPC `story_viewers` + field `liked` per penonton.
--   4) RPC `story_slides` (FROZEN) diperbaiki: branch 'followers'
--      (versi live masih 'registered' — ikut semua RPC story lain) +
--      field text_scale & text_rotation yang hilang + like_count/liked.
-- ============================================================

-- ── 1. Tabel like ─────────────────────────────────────────────
create table if not exists public.story_likes (
  story_id   uuid not null references public.stories(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);
create index if not exists idx_story_likes_user on public.story_likes(user_id);

alter table public.story_likes enable row level security;

-- Baca: like milik sendiri (client cek "apakah saya sudah like") atau
-- penonton slide MILIK saya (tidak dipakai client kini, tapi aman).
drop policy if exists story_likes_select on public.story_likes;
create policy story_likes_select on public.story_likes
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.stories s
               where s.id = story_id and s.author_id = auth.uid())
  );

-- ── 2. RPC toggle like ────────────────────────────────────────
-- Sekali tap: kalau sudah like → unlike; belum → like. Return count
-- terbaru supaya client bisa optimistic + koreksi.
create or replace function public.toggle_story_like(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_liked boolean;
  v_count int;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  -- Guard: story aktif + boleh dilihat (visibility/blokir), atau milik sendiri.
  if not exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and s.expires_at > now()
      and (
        s.author_id = v_uid
        or (
          (s.visibility = 'everyone')
          or (s.visibility = 'followers' and exists (
                select 1 from public.follows f
                where f.follower_id = v_uid and f.followee_id = s.author_id))
          or (s.visibility = 'friends' and public._are_friends(v_uid, s.author_id))
        )
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = v_uid and b.blocked_id = s.author_id)
             or (b.blocker_id = s.author_id and b.blocked_id = v_uid)
        )
      )
  ) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  delete from public.story_likes
  where story_id = p_story_id and user_id = v_uid;
  if found then
    v_liked := false;
  else
    insert into public.story_likes (story_id, user_id)
    values (p_story_id, v_uid)
    on conflict (story_id, user_id) do nothing;
    v_liked := true;
  end if;

  select count(*) into v_count
  from public.story_likes where story_id = p_story_id;
  return jsonb_build_object('ok', true, 'liked', v_liked, 'count', v_count);
end;
$fn$;

-- ── 3. story_viewers + liked ──────────────────────────────────
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
  if not exists (select 1 from public.stories s
                 where s.id = p_story_id and s.author_id = auth.uid()) then
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

-- ── 4. story_slides: branch 'followers' + skala/rotasi + like ─
create or replace function public.story_slides(p_author uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'image_path', s.image_path,
    'text_overlay', s.text_overlay,
    'text_x', s.text_x,
    'text_y', s.text_y,
    'text_color', s.text_color,
    'text_size', s.text_size,
    'text_scale', s.text_scale,
    'text_rotation', s.text_rotation,
    'text_bg', s.text_bg,
    'visibility', s.visibility,
    'like_count', (select count(*) from public.story_likes l where l.story_id = s.id),
    'liked', exists (select 1 from public.story_likes l
                     where l.story_id = s.id and l.user_id = auth.uid()),
    'created_at', s.created_at
  ) order by s.created_at asc), '[]'::jsonb)
  into result
  from public.stories s
  where s.author_id = p_author
    and s.expires_at > now()
    and (
      s.author_id = auth.uid()
      or (
        (s.visibility = 'everyone')
        or (s.visibility = 'followers' and exists (
              select 1 from public.follows f
              where f.follower_id = auth.uid()
                and f.followee_id = s.author_id))
        or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id))
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
           or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
      )
    );
  return result;
end;
$fn$;

-- ── 5. Grants ─────────────────────────────────────────────────
revoke execute on function public.toggle_story_like(uuid) from public, anon;
grant execute on function public.toggle_story_like(uuid) to authenticated;
revoke execute on function public.story_viewers(uuid) from public, anon;
grant execute on function public.story_viewers(uuid) to authenticated;
revoke execute on function public.story_slides(uuid) from public, anon;
grant execute on function public.story_slides(uuid) to authenticated;
