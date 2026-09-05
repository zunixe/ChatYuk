-- Story: anon boleh ikut bikin (dipaksa public) + opsi registered
-- berubah jadi "Pengikut" (followers).
--
-- Model visibility baru:
--   'everyone'   → semua orang (anon + registered)
--   'followers'  → hanya pengikut author (mengikuti author = follows)
--   'friends'    → hanya teman 2 arah
-- Aturan insert:
--   - Registered: pilih salah satu dari 3 opsi (default 'followers').
--   - Anon: BOLEH bikin, tapi DIPAKSA 'everyone' (server override —
--     apa pun yang dikirim client, jadikan public).

-- Story: ganti model visibility 'registered' → 'followers' + jembatan
-- untuk client lama (masih kirim 'registered').

-- 0) Trigger jembatan RACE-SAFE: client build lama masih mengirim
--    'registered' → rewrite jadi 'followers' SEBELUM constraint swap,
--    supaya tidak ada celah waktu yang bisa gagal ADD CONSTRAINT.
create or replace function public.fix_story_visibility() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.visibility = 'registered' then
    new.visibility := 'followers';
  end if;
  return new;
end; $$;

drop trigger if exists trg_fix_story_visibility on public.stories;
create trigger trg_fix_story_visibility
  before insert or update on public.stories
  for each row execute function public.fix_story_visibility();

-- 1) Data lama pindah ke 'followers' (trigger juga menutup row baru).
update public.stories set visibility='followers' where visibility='registered';

-- 2) Swap constraint — aman: trigger menjamin tidak ada 'registered' baru.
alter table public.stories
  drop constraint if exists stories_visibility_check;
alter table public.stories
  add constraint stories_visibility_check
  check (visibility in ('everyone','followers','friends'));
alter table public.stories
  alter column visibility set default 'followers';


-- 2) RLS insert: registered bebas pilih; anon hanya 'everyone'.
drop policy if exists stories_insert_own on public.stories;
create policy stories_insert_own on public.stories
  for insert to authenticated with check (
    author_id = auth.uid()
    and (select count(*) from public.stories
         where author_id = auth.uid()
           and created_at >= now() - interval '24 hours') < 10
    and (
      (public._viewer_is_registered())
      or visibility = 'everyone'
    )
  );

-- 3) RLS select / RPC: ganti 'registered' → 'followers' (pengikut =
--    ada row follows follower_id=viewer → followee_id=author).
drop policy if exists stories_select on public.stories;
create policy stories_select on public.stories
  for select to authenticated using (
    author_id = auth.uid()
    or (
      visibility = 'everyone'
      or (visibility = 'followers' and exists (
            select 1 from public.follows f
            where f.follower_id = auth.uid() and f.followee_id = author_id))
      or (visibility = 'friends' and public._are_friends(auth.uid(), author_id))
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = author_id)
         or (b.blocker_id = author_id and b.blocked_id = auth.uid())
    )
  );

-- 4) RPC story_tray
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
        )
      group by s.author_id
    ) a
  ) t;
  return result;
end;
$fn$;

-- 5) RPC story_slides
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

-- 6) RPC create_story: anon dipaksa 'everyone'; validasi opsi baru.
create or replace function public.create_story(
  p_image_path text,
  p_text_overlay text default '',
  p_text_x real default 0.5,
  p_text_y real default 0.85,
  p_text_color int default 0,
  p_text_size int default 1,
  p_text_bg boolean default false,
  p_visibility text default 'followers'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_id uuid;
  v_vis text;
  v_is_reg boolean;
begin
  v_is_reg := public._viewer_is_registered();
  -- Anon: DIPAKSA public. Registered: validasi pilihan.
  if not v_is_reg then
    v_vis := 'everyone';
  elsif p_visibility not in ('everyone','followers','friends') then
    raise exception 'Visibility tidak valid';
  else
    v_vis := p_visibility;
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
         v_vis
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$fn$;
revoke execute on function public.create_story(text,text,real,real,int,int,boolean,text) from public, anon;
grant execute on function public.create_story(text,text,real,real,int,int,boolean,text) to authenticated;
