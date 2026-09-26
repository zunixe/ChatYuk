-- ============================================================
-- Mute story ala IG: sembunyikan story author tanpa block/unfollow.
--
-- - Tabel `story_mutes` (muter → muted). RLS deny-by-default, tulis/baca
--   hanya lewat RPC SECURITY DEFINER.
-- - `story_tray()`: kirim flag `muted`, paksa `has_unseen=false` untuk
--   yang dibenamkan (tanpa ring biru), urutkan paling belakang.
-- - Tidak menyentuh fungsi FROZEN (story_slides/create_story tak diubah).
-- ============================================================

create table if not exists public.story_mutes (
  muter_id uuid not null references public.profiles (id) on delete cascade,
  muted_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint story_mutes_pkey primary key (muter_id, muted_id),
  constraint story_mutes_no_self check (muter_id <> muted_id)
);

alter table public.story_mutes enable row level security;

create index if not exists story_mutes_muter_idx
  on public.story_mutes (muter_id);

-- Benamkan author (idempoten).
create or replace function public.mute_story_author(p_author uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_author is null or p_author = me then
    raise exception 'Invalid author';
  end if;
  if not exists (select 1 from public.profiles where id = p_author) then
    raise exception 'Author not found';
  end if;
  insert into public.story_mutes (muter_id, muted_id)
  values (me, p_author)
  on conflict do nothing;
end; $$;

revoke execute on function public.mute_story_author(uuid) from public, anon;
grant execute on function public.mute_story_author(uuid) to authenticated;

-- Buka benaman (idempoten).
create or replace function public.unmute_story_author(p_author uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  delete from public.story_mutes
   where muter_id = me and muted_id = p_author;
end; $$;

revoke execute on function public.unmute_story_author(uuid) from public, anon;
grant execute on function public.unmute_story_author(uuid) to authenticated;

-- Tray + flag muted (badan disalin persis dari versi live + 3 baris mute).
create or replace function public.story_tray()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  select coalesce(jsonb_agg(t.obj order by t.sort_own desc, t.sort_muted asc, t.sort_unseen desc, t.latest_at desc), '[]'::jsonb)
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
        'has_unseen', a.unseen_count > 0 and not a.muted,
        'own', a.author_id = auth.uid(),
        'muted', a.muted
      ) as obj,
      (a.author_id = auth.uid()) as sort_own,
      coalesce(a.muted, false) as sort_muted,
      (a.unseen_count > 0 and not coalesce(a.muted, false)) as sort_unseen,
      a.latest_at
    from (
      select s.author_id,
             max(s.author_name) as author_name,
             -- Avatar di-mask sesuai profile_photo_visibility (bukan mentah).
             case when public.privacy_can_view(s.author_id, 'profile_photo', auth.uid())
                  then (select avatar from public.profiles p where p.id = s.author_id)
                  else '' end as avatar,
             (select is_registered from public.profiles p where p.id = s.author_id) as is_registered,
             count(*) as slide_count,
             (select s2.image_path from public.stories s2
              where s2.author_id = s.author_id and s2.expires_at > now()
              order by s2.created_at desc limit 1) as thumb_path,
             max(s.created_at) as latest_at,
             exists (
               select 1 from public.story_mutes m
               where m.muter_id = auth.uid() and m.muted_id = s.author_id
             ) as muted,
             count(*) filter (
               where not exists (
                 select 1 from public.story_views v
                 where v.story_id = s.id and v.viewer_id = auth.uid()
               )
             ) as unseen_count
      from public.stories s
      where s.expires_at > now()
        -- Privacy story: author yang menutup story-nya tidak muncul di tray.
        and public.privacy_can_view(s.author_id, 'story', auth.uid())
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
$function$;
