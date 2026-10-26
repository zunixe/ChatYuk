-- RPC DAFTAR untuk UI moderasi (moderator negara & admin) + badge publik.
--
-- RLS tabel mentah membatasi baca ke baris sendiri/admin, sehingga UI
-- moderator butuh RPC security definer yang memverifikasi peran.
--
-- SAFE: fungsi RPC baru (read-only); tidak mengubah policy/tabel.
create or replace function public.moderator_console(p_country text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  v_ok boolean;
  v_apps jsonb;
  v_permits jsonb;
  v_reports jsonb;
  v_mods jsonb;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  v_ok := public.is_chatyuk_admin(me)
       or public.is_country_moderator(p_country, me);
  if not v_ok then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'uid', a.uid, 'reason', a.reason,
           'created_at', a.created_at,
           'nickname', pr.nickname)
         order by a.created_at desc), '[]'::jsonb)
    into v_apps
    from public.moderator_applications a
    left join public.profiles pr on pr.id = a.uid
   where a.scope = 'country' and a.scope_value = p_country
     and a.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'uid', s.uid, 'status', s.status, 'reason', s.reason,
           'requested_at', s.requested_at,
           'nickname', pr.nickname)
         order by s.requested_at desc), '[]'::jsonb)
    into v_permits
    from public.country_send_permits s
    left join public.profiles pr on pr.id = s.uid
   where s.country = p_country and s.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'message_id', r.message_id,
           'reports', r.n,
           'room_id', max(r.room_id),
           'reason_code', max(r.reason_code),
           'last_at', max(r.created_at))
         order by max(r.created_at) desc), '[]'::jsonb)
    into v_reports
    from public.reports r
    join public.messages m on m.id::text = r.message_id
    join public.rooms ro on ro.id = m.room_id
   where r.message_id is not null and r.status = 'open'
     and ro.country = p_country
   group by r.message_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'uid', cm.uid, 'granted_at', cm.granted_at,
           'nickname', pr.nickname)
         order by cm.granted_at desc), '[]'::jsonb)
    into v_mods
    from public.country_moderators cm
    left join public.profiles pr on pr.id = cm.uid
   where cm.scope = 'country' and cm.scope_value = p_country
     and cm.revoked_at is null;

  return jsonb_build_object(
    'applications', v_apps,
    'permits', v_permits,
    'reports', v_reports,
    'moderators', v_mods
  );
end;
$function$;

revoke execute on function public.moderator_console(text) from public, anon;
grant execute on function public.moderator_console(text) to authenticated;

-- Badge publik: siapa moderator negara apa (untuk ikon perisai di chat).
-- Hanya mengembalikan uid+country (bukan data pribadi lain).
create or replace function public.moderator_uids(p_uids uuid[])
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('uid', cm.uid,
                                               'country', cm.scope_value)), '[]'::jsonb)
    from public.country_moderators cm
   where cm.revoked_at is null
     and cm.scope = 'country'
     and cm.uid = any(coalesce(p_uids, array[]::uuid[]));
$function$;

revoke execute on function public.moderator_uids(uuid[]) from public, anon;
grant execute on function public.moderator_uids(uuid[]) to authenticated;

-- Status peran saya (untuk tombol Ajukan Moderator / buka konsol).
create or replace function public.my_moderation_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  v_countries text[];
  v_pending text[];
begin
  if me is null then
    return jsonb_build_object('moderates', '[]'::json, 'pending', '[]'::json);
  end if;
  select coalesce(array_agg(scope_value), array[]::text[]) into v_countries
    from public.country_moderators
   where uid = me and scope = 'country' and revoked_at is null;
  select coalesce(array_agg(scope_value), array[]::text[]) into v_pending
    from public.moderator_applications
   where uid = me and scope = 'country' and status = 'pending';
  return jsonb_build_object('moderates', to_jsonb(v_countries),
                            'pending', to_jsonb(v_pending));
end;
$function$;

revoke execute on function public.my_moderation_state() from public, anon;
grant execute on function public.my_moderation_state() to authenticated;
