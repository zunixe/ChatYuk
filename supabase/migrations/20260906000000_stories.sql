-- ============================================================
-- Story ala Instagram — tabel, RLS, RPC, viewer, cron purge.
--
-- Model data:
--   1 row = 1 SLIDE. Story seseorang = semua slide aktifnya
--   (expires_at > now()). Slide baru menumpuk (append), slide
--   lama tetap sampai kedaluwarsa 24 jam — sama seperti IG.
--
-- Visibility slide:
--   'everyone'   → anon + registered bisa lihat
--   'registered' → hanya user is_registered (DEFAULT — paling aman)
--   'friends'    → hanya teman 2 arah (friend_requests accepted)
--   Semua dikurangi blokir dua arah (pola posts_select).
-- ============================================================

-- 1) Tabel utama
create table if not exists public.stories (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references public.profiles(id) on delete cascade,
  author_name text not null default 'Anon',
  image_path  text not null,
  text_overlay text not null default '',
  text_x      real not null default 0.5,
  text_y      real not null default 0.85,
  text_color  int  not null default 0,             -- indeks palette StoryText (0-7)
  text_size   int  not null default 1,            -- 0=S 1=M 2=L (token client)
  text_bg     boolean not null default false,     -- pill semi-hitam on/off
  visibility  text not null default 'registered'
                check (visibility in ('everyone','registered','friends')),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours'
);
create index if not exists idx_stories_author on public.stories(author_id, created_at desc);
create index if not exists idx_stories_expires on public.stories(expires_at);

alter table public.stories enable row level security;

-- 2) Tabel penonton (untuk sheet "siapa yang melihat")
create table if not exists public.story_views (
  story_id   uuid not null references public.stories(id) on delete cascade,
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  viewed_at  timestamptz not null default now(),
  primary key (story_id, viewer_id)
);
create index if not exists idx_story_views_viewer on public.story_views(viewer_id);

alter table public.story_views enable row level security;

-- 3) RLS stories
-- Helper: apakah viewer is_registered?
create or replace function public._viewer_is_registered()
returns boolean language sql stable set search_path = public as $fn$
  select coalesce((select is_registered from public.profiles where id = auth.uid()), false)
$fn$;

-- Helper: teman 2 arah antara viewer & author? (friend_requests accepted)
create or replace function public._are_friends(a uuid, b uuid)
returns boolean language sql stable set search_path = public as $fn$
  select exists (
    select 1 from public.friend_requests fr
    where fr.status = 'accepted'
      and ((fr.from_id = a and fr.to_id = b)
        or (fr.from_id = b and fr.to_id = a))
  )
$fn$;

-- SELECT: author sendiri ATAU sesuai visibility, minus blokir.
drop policy if exists stories_select on public.stories;
create policy stories_select on public.stories
  for select to authenticated using (
    author_id = auth.uid()
    or (
      visibility = 'everyone'
      or (visibility = 'registered' and public._viewer_is_registered())
      or (visibility = 'friends' and public._are_friends(auth.uid(), author_id))
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = author_id)
         or (b.blocker_id = author_id and b.blocked_id = auth.uid())
    )
  );

-- INSERT: hanya registered (anon dilarang — bahaya konten), max 10 slide/hari.
drop policy if exists stories_insert_own on public.stories;
create policy stories_insert_own on public.stories
  for insert to authenticated with check (
    author_id = auth.uid()
    and public._viewer_is_registered()
    and (select count(*) from public.stories
         where author_id = auth.uid()
           and created_at >= now() - interval '24 hours') < 10
  );

-- DELETE: pemilik slide.
drop policy if exists stories_delete_own on public.stories;
create policy stories_delete_own on public.stories
  for delete to authenticated using (author_id = auth.uid());

-- 4) RLS story_views
-- SELECT: pemilik story ATAU viewer itu sendiri (untuk status seen).
drop policy if exists story_views_select on public.story_views;
create policy story_views_select on public.story_views
  for select to authenticated using (
    viewer_id = auth.uid()
    or exists (select 1 from public.stories s
               where s.id = story_id and s.author_id = auth.uid())
  );

-- INSERT: viewer ter-authenticate & punya akses ke story-nya.
drop policy if exists story_views_insert_own on public.story_views;
create policy story_views_insert_own on public.story_views
  for insert to authenticated with check (
    viewer_id = auth.uid()
    and exists (select 1 from public.stories s where s.id = story_id)
  );

-- 5) RPC — tray: daftar author + thumbnail slide terbaru + jumlah slide
--    + flag has_unseen (ring gradient/abu) + avatar/nickname author.
create or replace function public.story_tray()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  result jsonb;
begin
  -- Slides aktif milik sendiri dulu, lalu orang lain yang belum
  -- dilihat (terbaru), lalu yang sudah dilihat.
  select coalesce(jsonb_agg(t.obj order by t.sort_own desc, t.sort_unseen desc, t.latest_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'author_id', a.author_id,
        'author_name', a.author_name,
        'avatar', a.avatar,
        'is_registered', a.is_registered,
        'slide_count', a.slide_count,
        'thumb_path', a.thumb_path,
        'has_unseen', a.unseen_count > 0,
        'own', a.author_id = auth.uid()
      ) as obj,
      (a.author_id = auth.uid()) as sort_own,
      (a.unseen_count > 0) as sort_unseen,
      a.latest_at
    from (
      select s.author_id,
             max(s.author_name) as author_name,
             (select avatar from public.profiles p where p.id = s.author_id) as avatar,
             (select is_registered from public.profiles p where p.id = s.author_id) as is_registered,
             count(*) as slide_count,
             (select s2.image_path from public.stories s2
              where s2.author_id = s.author_id and s2.expires_at > now()
              order by s2.created_at desc limit 1) as thumb_path,
             max(s.created_at) as latest_at,
             count(*) filter (
               where not exists (
                 select 1 from public.story_views v
                 where v.story_id = s.id and v.viewer_id = auth.uid()
               )
             ) as unseen_count
      from public.stories s
      where s.expires_at > now()
        and (
          s.author_id = auth.uid()
          or (
            (s.visibility = 'everyone')
            or (s.visibility = 'registered' and public._viewer_is_registered())
            or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id))
          )
          and not exists (
            select 1 from public.blocks b
            where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
               or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
          )
        )
      group by s.author_id
    ) a
  ) t;
  return result;
end;
$fn$;

-- 6) RPC — slide satu author (urut terlama → terbaru), untuk viewer.
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
    'text_bg', s.text_bg,
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
        or (s.visibility = 'registered' and public._viewer_is_registered())
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

-- 7) RPC — buat slide baru (author = auth.uid(), snapshot nama terbaru).
create or replace function public.create_story(
  p_image_path text,
  p_text_overlay text default '',
  p_text_x real default 0.5,
  p_text_y real default 0.85,
  p_text_color int default 0,
  p_text_size int default 1,
  p_text_bg boolean default false,
  p_visibility text default 'registered'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_id uuid;
begin
  if p_visibility not in ('everyone','registered','friends') then
    raise exception 'Visibility tidak valid';
  end if;
  if length(coalesce(p_text_overlay, '')) > 300 then
    raise exception 'Teks terlalu panjang (max 300)';
  end if;
  insert into public.stories (
    author_id, author_name, image_path, text_overlay, text_x, text_y,
    text_color, text_size, text_bg, visibility
  )
  select auth.uid(),
         coalesce((select nickname from public.profiles where id = auth.uid()), 'Anon'),
         p_image_path, coalesce(p_text_overlay, ''),
         greatest(least(coalesce(p_text_x, 0.5), 1), 0),
         greatest(least(coalesce(p_text_y, 0.85), 1), 0),
         greatest(least(coalesce(p_text_color, 0), 7), 0),
         greatest(least(coalesce(p_text_size, 1), 2), 0),
         coalesce(p_text_bg, false),
         p_visibility
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$fn$;

-- 8) RPC — tandai slide dilihat (idempoten, RLS insert jaga akses).
create or replace function public.mark_story_seen(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if exists (select 1 from public.stories s
             where s.id = p_story_id and s.expires_at > now()
               and (s.author_id = auth.uid()
                    or (s.visibility = 'everyone')
                    or (s.visibility = 'registered' and public._viewer_is_registered())
                    or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id)))) then
    insert into public.story_views (story_id, viewer_id)
    values (p_story_id, auth.uid())
    on conflict (story_id, viewer_id) do nothing;
  end if;
  return jsonb_build_object('ok', true);
end;
$fn$;

-- 9) RPC — daftar penonton slide milik sendiri (pemilik only).
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
    'viewed_at', v.viewed_at
  ) order by v.viewed_at desc), '[]'::jsonb)
  into result
  from public.story_views v
  join public.profiles pr on pr.id = v.viewer_id
  where v.story_id = p_story_id;
  return result;
end;
$fn$;

-- 10) RPC — hapus slide (pemilik; admin via email guard).
create or replace function public.delete_story(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_path text;
begin
  select image_path into v_path from public.stories
  where id = p_story_id and (author_id = auth.uid() or coalesce(auth.email(),'') = 'zunixe@gmail.com');
  if v_path is null then
    raise exception 'Unauthorized';
  end if;
  delete from public.stories where id = p_story_id;
  return jsonb_build_object('ok', true, 'image_path', v_path);
end;
$fn$;

-- 11) Cron purge slide kedaluwarsa + file storage (jalanan aman: row saja,
--     file storage dibersihkan terpisah — Storage API tidak bisa via SQL).
create or replace function public.purge_expired_stories()
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare n int;
begin
  delete from public.stories where expires_at <= now();
  get diagnostics n = row_count;
  return n;
end;
$fn$;

select cron.schedule('purge-stories', '17 * * * *',
  $$select public.purge_expired_stories()$$)
where not exists (select 1 from cron.job where jobname = 'purge-stories');

-- 12) Realtime replication
alter publication supabase_realtime add table public.stories;
alter publication supabase_realtime add table public.story_views;

-- 13) Grants
revoke execute on function public.story_tray() from public, anon;
grant execute on function public.story_tray() to authenticated;
revoke execute on function public.story_slides(uuid) from public, anon;
grant execute on function public.story_slides(uuid) to authenticated;
revoke execute on function public.mark_story_seen(uuid) from public, anon;
grant execute on function public.mark_story_seen(uuid) to authenticated;
revoke execute on function public.story_viewers(uuid) from public, anon;
grant execute on function public.story_viewers(uuid) to authenticated;
revoke execute on function public.delete_story(uuid) from public, anon;
grant execute on function public.delete_story(uuid) to authenticated;
revoke execute on function public.create_story(text,text,real,real,int,int,boolean,text) from public, anon;
grant execute on function public.create_story(text,text,real,real,int,int,boolean,text) to authenticated;
