-- PENYESUAIAN AMBANG + AUTO-HIDE SELEKTIF (keputusan user 2026-10-26).
--
-- 1. Ambang DITURUNKAN agar moderator lebih mudah terbentuk:
--      lamaran moderator : >= 7 hari & >= 50 pesan (dari 30 hari & 100)
--      kandidat angkatan : >= 20 pesan (dari 50)
-- 2. Auto-hide HANYA untuk pornografi & kekerasan. Spam/penipuan/lainnya
--    tetap masuk antrean moderator (status 'open') tetapi TIDAK otomatis
--    menyembunyikan pesan — mencegah penyalahgunaan tombol lapor.
--
-- SAFE: `create or replace` 3 fungsi milik fitur ini (bukan FROZEN);
--       tidak menyentuh policy/RLS/tabel lain.
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
      'min_days', 7);
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

create or replace function public.moderator_candidates(p_country text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not (public.is_chatyuk_admin(me)
          or public.is_country_moderator(p_country, me)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'uid', t.uid, 'nickname', t.nickname, 'messages', t.n)
           order by t.n desc)
      from (
        select m.sender_id as uid,
               coalesce(max(pr.nickname), '?') as nickname,
               count(*) as n
          from public.messages m
          join public.rooms r on r.id = m.room_id
          left join public.profiles pr on pr.id = m.sender_id
         where r.is_private = false
           and r.country = p_country
           and m.sender_id <> me
           and not exists (
             select 1 from public.country_moderators cm
              where cm.uid = m.sender_id
                and cm.scope = 'country'
                and cm.scope_value = p_country
                and cm.revoked_at is null
           )
         group by m.sender_id
        having count(*) >= 20
         order by count(*) desc
         limit 30
      ) t
  ), '[]'::jsonb);
end;
$function$;

-- Auto-hide hanya untuk konten berat (pornografi/kekerasan).
create or replace function public.report_room_message(
  p_message_id text,
  p_reason_code text,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_room    text;
  v_sender  uuid;
  v_reporters integer;
  v_code    text := coalesce(nullif(p_reason_code, ''), 'other');
  v_hidden  boolean := false;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(p_message_id, '') = '' then
    raise exception 'message_required' using errcode = '22023';
  end if;

  select m.room_id, m.sender_id into v_room, v_sender
    from public.messages m where m.id::text = p_message_id;
  if v_room is null then
    raise exception 'message_not_found' using errcode = 'P0002';
  end if;
  if v_sender = me then
    return jsonb_build_object('ok', false, 'error', 'own_message');
  end if;

  insert into public.reports
    (reporter_id, reported_id, reason, message_id, room_id, reason_code)
  values (me, v_sender, coalesce(p_note, ''), p_message_id, v_room, v_code)
  on conflict (reporter_id, message_id) where message_id is not null do update
    set reason_code = excluded.reason_code,
        reason = excluded.reason,
        status = 'open',
        created_at = now();

  select count(distinct r.reporter_id) into v_reporters
    from public.reports r
   where r.message_id = p_message_id
     and r.status <> 'dismissed';

  -- Hanya pornografi/kekerasan yang otomatis disembunyikan.
  if v_reporters >= 3 and v_code in ('porn', 'violence') then
    update public.messages set is_deleted = true
     where id::text = p_message_id and coalesce(is_deleted, false) = false;
    if found then
      v_hidden := true;
      insert into public.admin_alerts (kind, severity, message, detail)
      values ('reported_media', 'high',
              'Pesan disembunyikan otomatis (>=3 laporan pornografi/kekerasan)',
              jsonb_build_object('message_id', p_message_id,
                                 'room_id', v_room,
                                 'reporters', v_reporters,
                                 'reason_code', v_code));
    end if;
  end if;

  return jsonb_build_object('ok', true, 'reporters', v_reporters,
                            'auto_hidden', v_hidden);
end;
$function$;
