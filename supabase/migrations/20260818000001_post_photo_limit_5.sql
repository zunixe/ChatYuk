-- ============================================================
-- Batasi foto per posting jadi maksimal 5 (sebelumnya 10).
-- ============================================================

create or replace function public.create_post(
  p_text text default '',
  p_image_paths text[] default '{}',
  p_visibility text default 'public'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  am_registered boolean; my_name text; my_gender text;
  daily_lim int; today_count int; new_id uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if p_visibility not in ('public','followers','subscribers') then
    raise exception 'Invalid visibility';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = me;
  if am_registered is not true then raise exception 'Must be registered'; end if;

  p_text := btrim(coalesce(p_text, ''));
  if length(p_text) > 2000 then raise exception 'Post too long'; end if;
  if coalesce(array_length(p_image_paths, 1), 0) > 5 then
    raise exception 'Too many photos';
  end if;
  if p_text = '' and coalesce(array_length(p_image_paths, 1), 0) = 0 then
    raise exception 'Empty post';
  end if;

  select posts_daily_limit into daily_lim from public.app_settings where id = 'global';
  select count(*) into today_count from public.posts
    where author_id = me and created_at >= date_trunc('day', now());
  if today_count >= coalesce(daily_lim, 5) then
    raise exception 'Daily post limit reached';
  end if;

  insert into public.posts (author_id, author_name, author_gender, text, image_path, images, visibility)
    values (me, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_text, coalesce(p_image_paths[1], ''),
            coalesce(p_image_paths, '{}'::text[]), p_visibility)
    returning id into new_id;

  return jsonb_build_object(
    'ok', true,
    'id', new_id,
    'daily_remaining', greatest(0, coalesce(daily_lim, 5) - today_count - 1)
  );
end; $$;

revoke execute on function public.create_post(text, text[], text) from public, anon;
grant execute on function public.create_post(text, text[], text) to authenticated;