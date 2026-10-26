-- RPC MODERATOR NEGARA: lamaran, persetujuan, dan tindakan moderasi.
-- (lanjutan 20261026130000_country_moderators.sql)
--
-- Semua RPC security definer + guard peran eksplisit:
--   * apply_country_moderator   — user melamar (syarat: akun >=30 hari &
--                                 >=100 pesan di ROOM PUBLIK negara itu)
--   * decide_moderator_application — admin ATAU moderator negara tsb
--   * admin_set_country_moderator  — hanya admin (angkat/copot langsung)
--   * moderator_action          — moderator negara / admin; HANYA
--                                 hide/unhide/approve/reject/dismiss.
--                                 TIDAK bisa blokir akun / ubah profil.
--
-- SAFE: fungsi RPC baru; tidak mengubah policy/tabel yang ada.
--       Fitur terdampak: moderasi room publik (baru).

-- ── 1. Melamar jadi moderator negara ───────────────────────────────────────
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
  v_moderator   boolean;
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

  -- Syarat kontribusi: akun >= 30 hari & >= 100 pesan di room publik NEGARA itu
  select p.created_at into v_created from public.profiles p where p.id = me;
  if v_created is null then
    raise exception 'profile_missing' using errcode = '42501';
  end if;
  if v_created > now() - interval '30 days' then
    return jsonb_build_object('ok', false, 'error', 'account_too_new',
      'min_days', 30);
  end if;

  select count(*)
    into v_msgs
    from public.messages m
    join public.rooms r on r.id = m.room_id
   where m.sender_id = me
     and r.is_private = false
     and r.country = p_country;

  if v_msgs < 100 then
    return jsonb_build_object('ok', false, 'error', 'not_enough_messages',
      'need', 100, 'have', v_msgs);
  end if;

  insert into public.moderator_applications (scope, scope_value, uid, reason)
  values ('country', p_country, me, coalesce(p_reason, ''))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'application_id', v_id);
end;
$function$;

revoke execute on function public.apply_country_moderator(text, text) from public, anon;
grant execute on function public.apply_country_moderator(text, text) to authenticated;

-- ── 2. Putuskan lamaran (admin / moderator negara) ────────────────────────
create or replace function public.decide_moderator_application(
  p_application_id bigint,
  p_approve        boolean,
  p_note           text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me   uuid := auth.uid();
  a    public.moderator_applications%rowtype;
  v_is_admin     boolean;
  v_is_moderator boolean;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into a from public.moderator_applications where id = p_application_id;
  if a.id is null then
    raise exception 'application_not_found' using errcode = 'P0002';
  end if;
  if a.status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'already_decided');
  end if;

  v_is_admin := public.is_chatyuk_admin(me);
  v_is_moderator := public.is_country_moderator(a.scope_value, me);
  if not (v_is_admin or v_is_moderator) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.moderator_applications
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = me,
         decided_at = now(),
         decision_note = coalesce(p_note, '')
   where id = p_application_id;

  if p_approve then
    insert into public.country_moderators (scope, scope_value, uid, granted_by, source)
    values ('country', a.scope_value, a.uid, me, 'application')
    on conflict (scope, scope_value, uid) do update
      set revoked_at = null, granted_by = me, granted_at = now();
  end if;

  insert into public.moderator_actions (scope, scope_value, uid, target_uid, action, note)
  values ('country', a.scope_value, me, a.uid,
          case when p_approve then 'grant_permit' else 'dismiss_report' end,
          case when p_approve then 'moderator_approved' else 'moderator_rejected' end);

  return jsonb_build_object('ok', true, 'approved', p_approve);
end;
$function$;

revoke execute on function public.decide_moderator_application(bigint, boolean, text) from public, anon;
grant execute on function public.decide_moderator_application(bigint, boolean, text) to authenticated;

-- ── 3. Admin angkat/copot moderator langsung ───────────────────────────────
create or replace function public.admin_set_country_moderator(
  p_country text,
  p_uid     uuid,
  p_grant   boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_grant then
    insert into public.country_moderators (scope, scope_value, uid, granted_by, source)
    values ('country', p_country, p_uid, me, 'admin')
    on conflict (scope, scope_value, uid) do update
      set revoked_at = null, granted_by = me, granted_at = now();
  else
    update public.country_moderators
       set revoked_at = now()
     where scope = 'country' and scope_value = p_country
       and uid = p_uid and revoked_at is null;
  end if;

  insert into public.moderator_actions (scope, scope_value, uid, target_uid, action, note)
  values ('country', p_country, me, p_uid,
          case when p_grant then 'grant_permit' else 'revoke_permit' end,
          'admin_set_moderator');

  return jsonb_build_object('ok', true, 'granted', p_grant);
end;
$function$;

revoke execute on function public.admin_set_country_moderator(text, uuid, boolean) from public, anon;
grant execute on function public.admin_set_country_moderator(text, uuid, boolean) to authenticated;

-- ── 4. Tindakan moderator pada pesan (hide/unhide) ────────────────────────
-- Sengaja TIDAK menyediakan aksi "blokir/suspend akun" — itu wewenang admin.
create or replace function public.moderator_hide_message(
  p_message_id text,
  p_hide       boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_room    text;
  v_country text;
  v_is_priv boolean;
  v_ok      boolean;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select m.room_id into v_room
    from public.messages m
   where m.id::text = p_message_id;
  if v_room is null then
    raise exception 'message_not_found' using errcode = 'P0002';
  end if;

  select r.country, r.is_private into v_country, v_is_priv
    from public.rooms r where r.id = v_room;

  if v_is_priv then
    -- Room privat: hanya admin (moderator negara tidak berwenang).
    v_ok := public.is_chatyuk_admin(me);
  else
    v_ok := public.is_chatyuk_admin(me)
         or public.is_country_moderator(v_country, me);
  end if;
  if not v_ok then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.messages
     set is_deleted = p_hide
   where id::text = p_message_id;

  insert into public.moderator_actions (scope, scope_value, uid, message_id, action)
  values ('country', coalesce(v_country, ''), me, p_message_id,
          case when p_hide then 'hide' else 'unhide' end);

  return jsonb_build_object('ok', true, 'hidden', p_hide);
end;
$function$;

revoke execute on function public.moderator_hide_message(text, boolean) from public, anon;
grant execute on function public.moderator_hide_message(text, boolean) to authenticated;
