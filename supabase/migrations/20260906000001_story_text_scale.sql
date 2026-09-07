-- Skala teks story (pinch-to-zoom di composer). Default 1.0 (lama).
-- create_story ganti signature (drop dulu — overload lama menumpuk,
-- pelajaran dari get_online_users). story_slides tambah field jsonb.

alter table public.stories
add column if not exists text_scale real not null default 1.0;

drop function if exists
  public.create_story(text,text,real,real,int,int,boolean,text);

create or replace function public.create_story(
  p_image_path text,
  p_text_overlay text default '',
  p_text_x real default 0.5,
  p_text_y real default 0.85,
  p_text_color int default 0,
  p_text_size int default 1,
  p_text_bg boolean default false,
  p_text_scale real default 1.0,
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
    text_color, text_size, text_bg, text_scale, visibility
  )
  select auth.uid(),
         coalesce((select nickname from public.profiles where id = auth.uid()), 'Anon'),
         p_image_path, coalesce(p_text_overlay, ''),
         greatest(least(coalesce(p_text_x, 0.5), 1), 0),
         greatest(least(coalesce(p_text_y, 0.85), 1), 0),
         greatest(least(coalesce(p_text_color, 0), 7), 0),
         greatest(least(coalesce(p_text_size, 1), 2), 0),
         coalesce(p_text_bg, false),
         greatest(least(coalesce(p_text_scale, 1.0), 3.0), 0.5),
         p_visibility
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$fn$;

revoke execute on function
  public.create_story(text,text,real,real,int,int,boolean,real,text)
  from public, anon;
grant execute on function
  public.create_story(text,text,real,real,int,int,boolean,real,text)
  to authenticated;

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
    'text_scale', s.text_scale,
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
