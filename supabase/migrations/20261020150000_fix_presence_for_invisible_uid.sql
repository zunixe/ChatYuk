-- app_settings.invisible_admin_uid is text (default ''); presence_for declared it
-- as uuid, so every call failed with 22P02 when casting the empty string.
create or replace function public.presence_for(p_uids uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  invisible_uid text;
  arr jsonb;
begin
  select nullif(s.invisible_admin_uid, '') into invisible_uid
    from public.app_settings s where s.id = 'global';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',        p.id,
    'nickname',  p.nickname,
    'gender',    p.gender,
    'age',       p.age,
    'country',   p.country,
    'city',      p.city,
    'is_registered', p.is_registered,
    'avatar',    case when public.privacy_can_view(p.id, 'profile_photo', me)
                      then p.avatar else '' end,
    'status',    case when public.privacy_can_view(p.id, 'presence', me)
                      then p.status else 'offline' end,
    'last_seen', case when public.privacy_can_view(p.id, 'last_seen', me)
                      then p.last_seen else null end,
    'about',     case when public.privacy_can_view(p.id, 'about', me)
                      then p.about else '' end
  )), '[]'::jsonb) into arr
  from public.profiles p
  where p.id = any(coalesce(p_uids, '{}'::uuid[]))
    and p.id <> coalesce(me, '00000000-0000-0000-0000-000000000000'::uuid)
    and (invisible_uid is null or p.id::text <> invisible_uid)
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = me and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = me)
    );

  return arr;
end;
$function$;
