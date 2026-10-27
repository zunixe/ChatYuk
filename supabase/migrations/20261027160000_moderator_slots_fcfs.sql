-- SLOT MODERATOR: MAKS 2 PER NEGARA + SIAPA CEPAT DIA DAPAT + KELUAR SENDIRI
-- (keputusan produk 2026-10-27)
--
-- 1. Satu negara maksimal 2 moderator AKTIF (revoked_at is null). Semua jalur
--    pengangkatan (lamaran mandiri, angkat rekan, admin) menghormati batas
--    ini; dikunci advisory-lock per negara supaya 2 lamaran serentak tidak
--    sama-sama lolos cek slot.
-- 2. LAMARAN LANGSUNG DITETAPKAN: user yang memenuhi syarat (umur akun
--    >= 7 hari & >= 50 pesan publik di negaranya) langsung menjadi moderator
--    begitu melamar — "siapa cepat dia dapat", tanpa menunggu admin.
-- 3. Moderator bisa KELUAR SENDIRI lewat `moderator_resign()` — slot langsung
--    terbuka lagi, panel lamaran muncul kembali bagi user yang memenuhi
--    syarat; begitu slot terisi, panel hilang dari user lain.
-- 4. `my_moderation_state()` ditambah `eligible` + `slot_open` (+ angka slot)
--    supaya klien bisa menyembunyikan panel moderasi bagi yang tak memenuhi
--    syarat / slot penuh (keputusan VISIBILITAS tetap divalidasi ulang server
--    saat lamaran).
-- 5. Admin panel diberi RPC ringan `admin_moderation_activity()` (hitungan +
--    timestamp terakhir, bukan daftar penuh) untuk notifikasi aktivitas
--    moderasi: permohonan izin, laporan, tinjauan, perubahan moderator.
--
-- menyentuh: apply_country_moderator, moderator_set_colleague,
--            decide_moderator_application, admin_set_country_moderator,
--            my_moderation_state
--
-- SAFE: `create or replace` 5 fungsi MILIK FITUR INI + 2 fungsi BARU +
--       3 index parsial ADITIF. Tidak menyentuh policy/RLS/tabel bersama.
--       Fitur terdampak: moderasi room publik (lamaran moderator), profil.

-- ── 1. Index pendukung notifikasi aktivitas (aditif) ──────────────────────
create index if not exists messages_needs_review_idx
  on public.messages (created_at desc)
  where needs_review = true and coalesce(is_deleted, false) = false; -- SAFE: index aditif pada kolom fitur moderasi; tidak mengubah data/policy.

create index if not exists reports_open_idx
  on public.reports (created_at desc)
  where status = 'open'; -- SAFE: index aditif kolom status milik fitur laporan.

create index if not exists moderator_actions_grant_idx
  on public.moderator_actions (created_at desc)
  where action in ('grant_permit', 'revoke_permit'); -- SAFE: index aditif untuk RPC aktivitas admin.

-- ── 2. Hitungan moderator aktif satu negara ───────────────────────────────
create or replace function public.active_moderator_count(p_country text)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $function$
  select count(*)::int
    from public.country_moderators
   where scope = 'country'
     and scope_value = p_country
     and revoked_at is null;
$function$;

-- ── 3. Lamaran moderator: SIAPA CEPAT DIA DAPAT ───────────────────────────
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
  me        uuid := auth.uid();
  v_created timestamptz;
  v_msgs    integer;
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

  -- SIAPA CEPAT DIA DAPAT: kunci per-negara supaya 2 lamaran serentak tidak
  -- sama-sama lolos cek slot lalu membusukkan batas 2 moderator.
  perform pg_advisory_xact_lock(hashtext('modslot:' || p_country));

  if public.active_moderator_count(p_country) >= 2 then
    return jsonb_build_object('ok', false, 'error', 'slots_full', 'max', 2);
  end if;

  -- ADMIN: langsung diangkat (tanpa syarat kontribusi), tetap hormati slot.
  if public.is_chatyuk_admin(me) then
    insert into public.country_moderators
      (scope, scope_value, uid, source, granted_by)
    values ('country', p_country, me, 'admin', me)
    on conflict (scope, scope_value, uid) do update
      set revoked_at = null, granted_by = me, granted_at = now();

    insert into public.moderator_actions
      (scope, scope_value, uid, target_uid, action, note)
    values ('country', p_country, me, me, 'grant_permit',
            'admin_self_appoint');

    return jsonb_build_object('ok', true, 'already_moderator', true);
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

  -- Slot terbuka & syarat terpenuhi → LANGSUNG DITETAPKAN (bukan menunggu).
  insert into public.country_moderators
    (scope, scope_value, uid, source, granted_by)
  values ('country', p_country, me, 'application', me)
  on conflict (scope, scope_value, uid) do update
    set revoked_at = null, granted_by = me, granted_at = now();

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', p_country, me, me, 'grant_permit', 'auto_grant_fcfs');

  -- Tutup lamaran lama miliknya di negara ini (kalau ada) agar tidak
  -- menggantung sebagai pending.
  update public.moderator_applications
     set status = 'approved', decided_by = me, decided_at = now(),
         decision_note = 'auto_grant_fcfs'
   where uid = me and scope = 'country' and scope_value = p_country
     and status = 'pending';

  return jsonb_build_object('ok', true, 'granted', true);
end;
$function$;

revoke execute on function public.apply_country_moderator(text, text) from public, anon;
grant execute on function public.apply_country_moderator(text, text) to authenticated;

-- ── 4. Angkat/copot rekan moderator: hormati batas 2 slot ─────────────────
create or replace function public.moderator_set_colleague(
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
  me      uuid := auth.uid();
  v_admin boolean;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  v_admin := public.is_chatyuk_admin(me);
  if not (v_admin or public.is_country_moderator(p_country, me)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_uid = me then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;
  if coalesce(p_country, '') = '' then
    raise exception 'country_required' using errcode = '22023';
  end if;

  if p_grant then
    perform pg_advisory_xact_lock(hashtext('modslot:' || p_country));
    -- Target yang tadinya pernah moderator & diangkat ulang tidak menambah
    -- slot baru → kecualikan dari hitungan.
    if public.active_moderator_count(p_country)
       - (case when public.is_country_moderator(p_country, p_uid) then 1 else 0 end)
       >= 2 then
      return jsonb_build_object('ok', false, 'error', 'slots_full', 'max', 2);
    end if;

    insert into public.country_moderators
      (scope, scope_value, uid, granted_by, source)
    values ('country', p_country, p_uid, me,
            case when v_admin then 'admin' else 'moderator' end)
    on conflict (scope, scope_value, uid) do update
      set revoked_at = null, granted_by = me, granted_at = now(),
          source = case when v_admin then 'admin' else 'moderator' end;
  else
    update public.country_moderators
       set revoked_at = now()
     where scope = 'country' and scope_value = p_country
       and uid = p_uid and revoked_at is null;
  end if;

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', p_country, me, p_uid,
          case when p_grant then 'grant_permit' else 'revoke_permit' end,
          case when p_grant then 'moderator_appointed' else 'moderator_revoked' end);

  return jsonb_build_object('ok', true, 'granted', p_grant);
end;
$function$;

revoke execute on function public.moderator_set_colleague(text, uuid, boolean) from public, anon;
grant execute on function public.moderator_set_colleague(text, uuid, boolean) to authenticated;

-- ── 5. Putuskan lamaran (jalur legacy/admin): hormati batas 2 slot ────────
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

  if p_approve then
    perform pg_advisory_xact_lock(hashtext('modslot:' || a.scope_value));
    if public.active_moderator_count(a.scope_value)
       - (case when public.is_country_moderator(a.scope_value, a.uid)
               then 1 else 0 end)
       >= 2 then
      return jsonb_build_object('ok', false, 'error', 'slots_full', 'max', 2);
    end if;
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

-- ── 6. Admin angkat/copot moderator: hormati batas 2 slot saat grant ──────
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
    perform pg_advisory_xact_lock(hashtext('modslot:' || p_country));
    if public.active_moderator_count(p_country)
       - (case when public.is_country_moderator(p_country, p_uid)
               then 1 else 0 end)
       >= 2 then
      return jsonb_build_object('ok', false, 'error', 'slots_full', 'max', 2);
    end if;

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

-- ── 7. Moderator keluar sendiri — slot langsung terbuka ───────────────────
create or replace function public.moderator_resign()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me     uuid := auth.uid();
  v_left text[];
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  with left_rows as (
    update public.country_moderators
       set revoked_at = now()
     where uid = me
       and scope = 'country'
       and revoked_at is null
    returning scope_value
  )
  select coalesce(array_agg(scope_value), array[]::text[]) into v_left
    from left_rows;

  if v_left is null or array_length(v_left, 1) = 0 then
    return jsonb_build_object('ok', true, 'was_moderator', false);
  end if;

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  select 'country', c, me, me, 'revoke_permit', 'moderator_resign'
    from unnest(v_left) as c;

  return jsonb_build_object('ok', true, 'was_moderator', true,
                            'countries', to_jsonb(v_left));
end;
$function$;

revoke execute on function public.moderator_resign() from public, anon;
grant execute on function public.moderator_resign() to authenticated;

-- ── 8. my_moderation_state: + eligible & slot (visibilitas panel Profil) ──
create or replace function public.my_moderation_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_countries text[];
  v_pending   text[];
  v_revoked   jsonb;
  v_country   text;
  v_created   timestamptz;
  v_msgs      integer := 0;
  v_eligible  boolean := false;
  v_open      boolean := false;
  v_count     integer := 0;
begin
  if me is null then
    return jsonb_build_object(
      'moderates', '[]'::json, 'pending', '[]'::json, 'revoked', '[]'::json,
      'eligible', false, 'slot_open', false, 'slot_count', 0, 'slot_max', 2);
  end if;

  select coalesce(array_agg(scope_value), array[]::text[]) into v_countries
    from public.country_moderators
   where uid = me and scope = 'country' and revoked_at is null;

  select coalesce(array_agg(scope_value), array[]::text[]) into v_pending
    from public.moderator_applications
   where uid = me and scope = 'country' and status = 'pending';

  select country, created_at into v_country, v_created
    from public.profiles where id = me;

  if coalesce(v_country, '') <> '' and v_created is not null then
    -- Syarat sama dengan apply_country_moderator: umur akun >= 7 hari &
    -- >= 50 pesan publik di negaranya sendiri.
    if v_created <= now() - interval '7 days' then
      select count(*) into v_msgs
        from public.messages m
        join public.rooms r on r.id = m.room_id
       where m.sender_id = me
         and r.is_private = false
         and r.country = v_country;
      v_eligible := v_msgs >= 50;
    end if;

    v_count := public.active_moderator_count(v_country);
    v_open := v_count < 2;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', cm.scope_value, 'revoked_at', cm.revoked_at)
         order by cm.revoked_at desc), '[]'::jsonb)
    into v_revoked
    from public.country_moderators cm
   where cm.uid = me
     and cm.revoked_at is not null
     and exists (
       select 1 from public.moderator_actions ma
        where ma.uid = me and ma.target_uid = me
          and ma.scope_value = cm.scope_value
          and ma.note in ('auto_revoke_country_change', 'moderator_resign')
     )
   limit 5;

  return jsonb_build_object(
    'moderates', to_jsonb(v_countries),
    'pending', to_jsonb(v_pending),
    'revoked', v_revoked,
    'country', v_country,
    'eligible', v_eligible,
    'slot_open', v_open,
    'slot_count', v_count,
    'slot_max', 2
  );
end;
$function$;

-- ── 9. Aktivitas moderasi untuk notifikasi ADMIN (ringan) ─────────────────
create or replace function public.admin_moderation_activity()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'permits', (select count(*) from public.country_send_permits
                 where status = 'pending'),
    'permits_at', (select max(requested_at) from public.country_send_permits
                    where status = 'pending'),
    'reports', (select count(*) from public.reports
                 where status = 'open' and message_id is not null),
    'reports_at', (select max(created_at) from public.reports
                    where status = 'open' and message_id is not null),
    'reviews', (select count(*) from public.messages
                 where needs_review = true
                   and coalesce(is_deleted, false) = false),
    'reviews_at', (select max(created_at) from public.messages
                    where needs_review = true
                      and coalesce(is_deleted, false) = false),
    'mods_at', (select max(created_at) from public.moderator_actions
                 where action in ('grant_permit', 'revoke_permit')),
    'mods_last', (
      select jsonb_build_object(
               'country', ma.scope_value,
               'action', ma.action,
               'note', ma.note,
               'nickname', coalesce(tp.nickname, '?'),
               'created_at', ma.created_at)
        from public.moderator_actions ma
        left join public.profiles tp on tp.id = ma.target_uid
       where ma.action in ('grant_permit', 'revoke_permit')
       order by ma.created_at desc
       limit 1
    )
  );
end;
$function$;

revoke execute on function public.admin_moderation_activity() from public, anon;
grant execute on function public.admin_moderation_activity() to authenticated;
