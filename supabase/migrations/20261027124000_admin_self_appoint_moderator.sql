-- ADMIN tidak perlu "melamar" jadi moderator: langsung diangkat untuk
-- negaranya sendiri (satu klik), tanpa syarat umur/pesan — admin toh sudah
-- bisa mengangkat siapa pun lewat `moderator_set_colleague`.
--
-- Latar: akun admin melaporkan "ajukan jadi moderator gagal" karena
-- `home_country = Armenia` sedangkan pesan publiknya 0 di Armenia (29 di
-- Indonesia) → `not_enough_messages`. Aturan itu BENAR untuk user biasa,
-- tetapi admin tidak seharusnya diminta melamar.
--
-- SAFE: `create or replace` 1 fungsi milik fitur ini; menambah baris di
--       `country_moderators` + audit `moderator_actions`.
create or replace function public.apply_country_moderator(
  p_country text,
  p_reason  text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me            uuid := auth.uid();
  v_created     timestamptz;
  v_msgs        integer;
  v_pending     boolean;
  v_id          bigint;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(p_country, '') = '' then
    raise exception 'country_required' using errcode = '22023';
  end if;

  if public.is_country_moderator(p_country, me) then
    return jsonb_build_object('ok', true, 'already_moderator', true);
  end if;

  -- ADMIN: langsung diangkat (tanpa lamaran, tanpa syarat kontribusi).
  if public.is_chatyuk_admin(me) then
    insert into public.country_moderators
      (scope, scope_value, uid, source, granted_by)
    values ('country', p_country, me, 'admin', me)
    on conflict do nothing;

    insert into public.moderator_actions
      (scope, scope_value, uid, target_uid, action, note)
    values ('country', p_country, me, me, 'grant_permit',
            'admin_self_appoint');

    return jsonb_build_object('ok', true, 'already_moderator', true);
  end if;

  select exists (
    select 1 from public.moderator_applications a
     where a.scope = 'country' and a.scope_value = p_country
       and a.uid = me and a.status = 'pending'
  ) into v_pending;
  if v_pending then
    return jsonb_build_object('ok', true, 'already_pending', true);
  end if;

  select p.created_at into v_created from public.profiles p where p.id = me;
  if v_created is null then
    raise exception 'profile_missing' using errcode = '42501';
  end if;
  if v_created > now() - interval '7 days' then
    return jsonb_build_object('ok', false, 'error', 'account_too_new',
      'min_days', 7,
      'have_days', floor(extract(epoch from now() - v_created) / 86400)::int);
  end if;

  select count(*)
    into v_msgs
    from public.messages m
    join public.rooms r on r.id = m.room_id
   where m.sender_id = me
     and r.is_private = false
     and r.country = p_country;

  if v_msgs < 50 then
    return jsonb_build_object('ok', false, 'error', 'not_enough_messages',
      'need', 50, 'have', v_msgs);
  end if;

  insert into public.moderator_applications (scope, scope_value, uid, reason)
  values ('country', p_country, me, coalesce(p_reason, ''))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'application_id', v_id);
end;
$function$;
