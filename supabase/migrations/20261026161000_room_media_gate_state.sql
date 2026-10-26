-- ALASAN GATE (untuk klien): kenapa media ditolak + status izin lintas negara.
--
-- Tanpa ini klien hanya tahu "tidak boleh" dan tidak bisa menampilkan aksi
-- yang tepat (ajukan izin vs aktivitas belum cukup).
--
-- SAFE: fungsi baru read-only; tidak mengubah apa pun.
create or replace function public.room_media_gate_state(p_room text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_private boolean;
  v_country text;
  v_home    text;
  v_allowed boolean;
  v_permit  text;
  v_min_days integer;
  v_min_msgs integer;
  v_created timestamptz;
  v_msgs    integer;
  v_reason  text;
begin
  if me is null then
    return jsonb_build_object('allowed', false, 'reason', 'not_authenticated');
  end if;

  select r.is_private, r.country into v_private, v_country
    from public.rooms r where r.id = p_room;
  if v_private is null then
    return jsonb_build_object('allowed', false, 'reason', 'room_not_found');
  end if;
  if v_private then
    return jsonb_build_object('allowed', true, 'reason', 'private_room',
                              'room_country', v_country);
  end if;

  select home_country into v_home from public.profiles where id = me;

  select status into v_permit from public.country_send_permits
   where uid = me and country = v_country;

  v_allowed := public.can_send_room_media(p_room, me);

  if v_allowed then
    return jsonb_build_object('allowed', true, 'reason', 'ok',
      'room_country', v_country, 'home_country', v_home,
      'permit_status', v_permit);
  end if;

  -- Tentukan alasan utama (urutan sama dengan can_send_room_media).
  if coalesce(v_home, '') <> '' and v_home <> coalesce(v_country, '') then
    if v_permit is distinct from 'approved' then
      return jsonb_build_object('allowed', false,
        'reason', case when v_permit = 'pending' then 'permit_pending'
                       else 'needs_permit' end,
        'room_country', v_country, 'home_country', v_home,
        'permit_status', v_permit);
    end if;
  end if;

  select coalesce(media_trust_min_days, 3), coalesce(media_trust_min_msgs, 20)
    into v_min_days, v_min_msgs from public.app_settings where id = 'global';

  select p.created_at into v_created from public.profiles p where p.id = me;
  if v_created is null then
    return jsonb_build_object('allowed', false, 'reason', 'profile_missing');
  end if;
  if v_created > now() - make_interval(days => v_min_days) then
    v_reason := 'account_too_new';
  else
    select count(*) into v_msgs
      from public.messages m
      join public.rooms r2 on r2.id = m.room_id
     where m.sender_id = me and r2.is_private = false;
    v_reason := case when v_msgs < v_min_msgs then 'not_enough_messages'
                     else 'blocked_other' end;
  end if;

  return jsonb_build_object('allowed', false, 'reason', v_reason,
    'room_country', v_country, 'home_country', v_home,
    'min_days', v_min_days, 'min_msgs', v_min_msgs,
    'have_msgs', coalesce(v_msgs, 0),
    'permit_status', v_permit);
end;
$function$;

revoke execute on function public.room_media_gate_state(text) from public, anon;
grant execute on function public.room_media_gate_state(text) to authenticated;
