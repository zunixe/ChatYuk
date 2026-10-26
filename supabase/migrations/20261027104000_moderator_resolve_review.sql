-- MODERATOR MENYELESAIKAN TINJAUAN MEDIA borderline (needs_review).
--
-- `p_hide = true`  → pesan disembunyikan (is_deleted) + flag dibersihkan.
-- `p_hide = false` → dianggap layak: hanya membersihkan flag.
-- Wilayah wewenang = negara moderator (atau admin lintas negara).
--
-- SAFE: 1 fungsi baru milik fitur ini; menulis `messages.needs_review`
--       dan (opsional) `messages.is_deleted` + audit `moderator_actions`.
--       Tidak mengubah policy/RLS.
create or replace function public.moderator_resolve_review(
  p_message_id text,
  p_hide boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me      uuid := auth.uid();
  v_country text;
  v_room  text;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select m.room_id, r.country into v_room, v_country
    from public.messages m
    join public.rooms r on r.id = m.room_id
   where m.id::text = p_message_id;
  if v_room is null then
    raise exception 'message_not_found' using errcode = 'P0002';
  end if;

  if not (public.is_chatyuk_admin(me)
          or public.is_country_moderator(v_country, me)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.messages
     set needs_review = false,
         is_deleted = case when p_hide then true else is_deleted end
   where id::text = p_message_id;

  insert into public.moderator_actions
    (scope, scope_value, uid, message_id, action, note)
  values ('country', v_country, me, p_message_id,
          case when p_hide then 'hide' else 'approve_media' end,
          'needs_review');

  return jsonb_build_object('ok', true, 'hidden', p_hide);
end;
$function$;

revoke execute on function public.moderator_resolve_review(text, boolean)
  from public, anon;
grant execute on function public.moderator_resolve_review(text, boolean)
  to authenticated;
