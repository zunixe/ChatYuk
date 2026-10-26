-- SATU NEGARA SAJA: `country` (didalam profil) menggantikan `home_country`.
--
-- Keputusan produk (2026-10-27):
--   * Tidak ada lagi `home_country` — aturan media & moderator memakai
--     `profiles.country`.
--   * Deteksi IP TIDAK menimpa negara (klien berhenti mengirim country saat
--     login). Hanya user sendiri yang boleh mengganti, lewat RPC resmi.
--   * Ganti negara DIBATASI 1x per 7 hari, dihitung dari perubahan terakhir.
--     Setelah berubah, masa lock 7 hari berjalan lagi.
--   * User yang belum pernah dikunci (`country_changed_at IS NULL`) boleh
--     membetulkan negaranya sekali tanpa menunggu (user baru / salah deteksi).
--   * MODERATOR yang pindah negara: jabatannya DICABUT otomatis (tidak
--     dipindah), tercatat di `moderator_actions`. Untuk kembali harus melamar
--     ulang / diangkat admin.
--   * Admin tidak terpengaruh (akses lintas negara via is_chatyuk_admin).
--
-- SAFE: drop 2 kolom + 2 trigger + 4 fungsi lama MILIK FITUR INI, lalu
--       menambah 1 kolom (country_changed_at) + 1 trigger guard + 2 RPC.
--       Tidak menyentuh policy/RLS tabel bersama.
--       Data lama diselamatkan lebih dulu (home_country -> country).
--       Fitur terdampak: aturan media room publik, lamaran moderator, profil.

-- ── 1. Selamatkan data lama: pilihan eksplisit user MENANG ─────────────────
update public.profiles
   set country = home_country
 where home_country is not null
   and btrim(home_country) <> ''
   and (country is null or country <> home_country);

-- ── 2. Kolom penanda lock ─────────────────────────────────────────────────
alter table public.profiles add column if not exists country_changed_at timestamptz;

-- Pengguna lama yang sudah punya negara: masa lock mulai hari ini (adil).
update public.profiles
   set country_changed_at = now()
 where country_changed_at is null
   and coalesce(btrim(country), '') <> '';

-- ── 3. Buang konsep lama ──────────────────────────────────────────────────
drop trigger if exists set_home_country_default_trg on public.profiles; -- SAFE: trigger milik fitur ini (digantikan guard country)
drop trigger if exists guard_home_country_trg on public.profiles; -- SAFE: trigger milik fitur ini (digantikan guard country)
drop function if exists public.set_home_country_default() ; -- SAFE: fungsi milik fitur ini, tak dipakai lagi
drop function if exists public.guard_home_country() ; -- SAFE: fungsi milik fitur ini, digantikan guard_country_lock
drop function if exists public.set_home_country(text) ; -- SAFE: digantikan set_my_country (aturan 7 hari)
drop function if exists public.admin_set_home_country(uuid, text) ; -- SAFE: digantikan admin_set_country (tanpa unset)
alter table public.profiles drop column if exists home_country; -- SAFE: data sudah diselamatkan ke country
alter table public.profiles drop column if exists home_country_changed_at; -- SAFE: digantikan country_changed_at

-- ── 4. Guard: negara terkunci 7 hari ─────────────────────────────────────
create or replace function public.guard_country_lock()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_trusted boolean :=
    coalesce(current_setting('chatyuk.country_ok', true), '') = '1';
begin
  -- Tidak ada perubahan → lolos.
  if new.country is not distinct from old.country
     and new.country_changed_at is not distinct from old.country_changed_at then
    return new;
  end if;

  -- Jalur resmi (RPC), admin, belum pernah dikunci, atau lock sudah lewat.
  if v_trusted
     or public.is_chatyuk_admin(auth.uid())
     or old.country_changed_at is null
     or old.country_changed_at <= now() - interval '7 days' then
    return new;
  end if;

  -- Terkunci: pertahankan nilai lama (tanpa error agar update kolom lain
  -- pada baris yang sama tetap berhasil).
  new.country := old.country;
  new.country_changed_at := old.country_changed_at;
  return new;
end;
$function$;

drop trigger if exists guard_country_lock_trg on public.profiles;
create trigger guard_country_lock_trg
  before update of country, country_changed_at on public.profiles
  for each row execute function public.guard_country_lock();

-- ── 5. RPC user: ganti negara (maks 1x / 7 hari) + cabut jabatan moderator ─
create or replace function public.set_my_country(p_country text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_country text := nullif(btrim(coalesce(p_country, '')), '');
  v_old     text;
  v_changed timestamptz;
  v_revoked text[];
  v_next    timestamptz;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_country is null then
    raise exception 'country_required' using errcode = '22023';
  end if;

  select country, country_changed_at into v_old, v_changed
    from public.profiles where id = me;

  if v_old is not null and v_old = v_country then
    return jsonb_build_object('ok', true, 'unchanged', true,
                              'country', v_country);
  end if;

  -- Lock 7 hari SEJAK PERUBAHAN TERAKHIR. Baris baru (NULL) bebas.
  if v_changed is not null and v_changed > now() - interval '7 days' then
    return jsonb_build_object(
      'ok', false,
      'error', 'cooldown',
      'next_change_at', (v_changed + interval '7 days'),
      'country', v_old
    );
  end if;

  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles
     set country = v_country,
         country_changed_at = now()
   where id = me;
  perform set_config('chatyuk.country_ok', '', true);

  -- MODERATOR pindah negara → jabatan dicabut (bukan dipindah).
  with revoked as (
    update public.country_moderators
       set revoked_at = now()
     where uid = me
       and revoked_at is null
       and scope = 'country'
       and scope_value <> v_country
    returning scope_value
  )
  select coalesce(array_agg(scope_value), array[]::text[])
    into v_revoked
    from revoked;

  if v_revoked is not null and array_length(v_revoked, 1) > 0 then
    insert into public.moderator_actions
      (scope, scope_value, uid, target_uid, action, note)
    select 'country', c, me, me, 'revoke_permit',
           'auto_revoke_country_change'
      from unnest(v_revoked) as c;
  end if;

  v_next := now() + interval '7 days';

  return jsonb_build_object(
    'ok', true,
    'country', v_country,
    'previous_country', v_old,
    'next_change_at', v_next,
    'revoked_moderator_for', to_jsonb(v_revoked)
  );
end;
$function$;

revoke execute on function public.set_my_country(text) from public, anon;
grant execute on function public.set_my_country(text) to authenticated;

-- ── 6. RPC admin: set negara user (tanpa cooldown, tanpa "kosongkan") ──────
create or replace function public.admin_set_country(p_uid uuid, p_country text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_country text := nullif(btrim(coalesce(p_country, '')), '');
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_uid is null then
    raise exception 'uid_required' using errcode = '22023';
  end if;
  if v_country is null then
    raise exception 'country_required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_uid) then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  perform set_config('chatyuk.country_ok', '1', true);
  update public.profiles
     set country = v_country,
         country_changed_at = now()
   where id = p_uid;
  perform set_config('chatyuk.country_ok', '', true);

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', v_country, me, p_uid, 'grant_permit',
          'admin_set_country:' || v_country);

  return jsonb_build_object('ok', true, 'uid', p_uid, 'country', v_country);
end;
$function$;

revoke execute on function public.admin_set_country(uuid, text) from public, anon;
grant execute on function public.admin_set_country(uuid, text) to authenticated;

-- ── 7. Aturan media & profil memakai `country` ────────────────────────────
create or replace function public.can_send_room_media(p_room text, p_uid uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_private   boolean;
  v_country   text;
  v_home      text;
  v_min_days  integer;
  v_min_msgs  integer;
  v_created   timestamptz;
  v_msgs      integer;
begin
  if p_uid is null or p_room is null then
    return false;
  end if;

  select r.is_private, r.country into v_private, v_country
    from public.rooms r where r.id = p_room;
  if v_private is null then
    return false;
  end if;

  if v_private then
    return true;
  end if;

  if public.is_chatyuk_admin(p_uid) then
    return true;
  end if;
  if public.is_country_moderator(v_country, p_uid) then
    return true;
  end if;

  -- LINTAS NEGARA: country beda dengan negara room → wajib izin approved.
  select country into v_home from public.profiles where id = p_uid;
  if coalesce(v_home, '') <> '' and v_home <> coalesce(v_country, '') then
    if not exists (
      select 1 from public.country_send_permits p
       where p.uid = p_uid and p.country = v_country and p.status = 'approved'
    ) then
      return false;
    end if;
  end if;

  select coalesce(media_trust_min_days, 3), coalesce(media_trust_min_msgs, 20)
    into v_min_days, v_min_msgs from public.app_settings where id = 'global';

  select p.created_at into v_created from public.profiles p where p.id = p_uid;
  if v_created is null then
    return false;
  end if;
  if v_created > now() - make_interval(days => v_min_days) then
    return false;
  end if;

  select count(*) into v_msgs
    from public.messages m
    join public.rooms r2 on r2.id = m.room_id
   where m.sender_id = p_uid and r2.is_private = false;

  return v_msgs >= v_min_msgs;
end;
$function$;

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

  select country into v_home from public.profiles where id = me;

  select status into v_permit from public.country_send_permits
   where uid = me and country = v_country;

  v_allowed := public.can_send_room_media(p_room, me);

  if v_allowed then
    return jsonb_build_object('allowed', true, 'reason', 'ok',
      'room_country', v_country, 'home_country', v_home,
      'permit_status', v_permit);
  end if;

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

-- ── 8. Izin kirim lintas negara: pakai `country` ──────────────────────────
create or replace function public.request_country_permit(
  p_country text,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me      uuid := auth.uid();
  v_home  text;
  v_row   public.country_send_permits%rowtype;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(p_country, '') = '' then
    raise exception 'country_required' using errcode = '22023';
  end if;

  select country into v_home from public.profiles where id = me;
  if v_home is not null and v_home = p_country then
    return jsonb_build_object('ok', true, 'not_needed', true);
  end if;

  select * into v_row from public.country_send_permits
   where uid = me and country = p_country;

  if v_row.id is not null then
    if v_row.status = 'approved' then
      return jsonb_build_object('ok', true, 'already_approved', true);
    end if;
    if v_row.status = 'pending' then
      return jsonb_build_object('ok', true, 'already_pending', true);
    end if;
    update public.country_send_permits
       set status = 'pending', reason = coalesce(p_reason, ''),
           requested_at = now(), decided_by = null, decided_at = null
     where id = v_row.id;
    return jsonb_build_object('ok', true, 'reopened', true);
  end if;

  insert into public.country_send_permits (uid, country, reason)
  values (me, p_country, coalesce(p_reason, ''));

  return jsonb_build_object('ok', true, 'requested', true);
end;
$function$;

-- ── 9. Profil publik: negara + kapan bisa diubah (untuk diri sendiri) ─────
create or replace function public.profile_public(p_user uuid default auth.uid())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  r public.profiles%rowtype;
  me uuid := auth.uid();
  v_is_me boolean := (p_user = auth.uid());
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;

  return jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case when public.privacy_can_view(r.id, 'presence', me)
                   then r.status else 'offline' end,
    'avatar', case when public.privacy_can_view(r.id, 'profile_photo', me) then r.avatar else '' end,
    'is_registered', r.is_registered,
    'needs_onboarding', coalesce(r.needs_onboarding, false),
    'login_at', r.login_at,
    'created_at', r.created_at,
    'last_seen', case when public.privacy_can_view(r.id, 'last_seen', me) then r.last_seen else null end,
    'about', case when public.privacy_can_view(r.id, 'about', me) then r.about else '' end,
    'hashtags', r.hashtags,
    'points', case when r.id = me then r.points else 0 end,
    'share_location', case when r.id = me then r.share_location else false end,
    'followers_count', r.followers_count,
    'following_count', r.following_count,
    'subscriber_count', r.subscriber_count,
    'subscription_price', r.subscription_price,
    'friends_count', r.friends_count,
    'phone', case when v_is_me then coalesce(r.phone, '') else '' end,
    'birth_date', case when v_is_me then r.birth_date else null end,
    'phone_verified_at',
      case when v_is_me then r.phone_verified_at else null end,
    -- Kapan negara boleh diubah lagi (khusus diri sendiri).
    'country_changed_at',
      case when v_is_me then r.country_changed_at else null end
  );
end;
$function$;

-- ── 10. Admin: ringkasan moderasi & pencarian user pakai `country` ────────
create or replace function public.admin_search_users(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  q  text := trim(coalesce(p_query, ''));
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if length(q) < 2 then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'uid', p.id, 'nickname', p.nickname,
             'country', p.country,
             'messages', (select count(*) from public.messages m
                          where m.sender_id = p.id))
           order by p.nickname)
      from (
        select pr.id, pr.nickname, pr.country
          from public.profiles pr
         where pr.nickname ilike '%' || q || '%'
            or pr.id::text = q
         order by pr.nickname
         limit 20
      ) p
  ), '[]'::jsonb);
end;
$function$;

revoke execute on function public.admin_search_users(text) from public, anon;
grant execute on function public.admin_search_users(text) to authenticated;

create or replace function public.admin_moderation_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  v_permits jsonb;
  v_apps jsonb;
  v_reports jsonb;
  v_reviews jsonb;
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', s.country, 'uid', s.uid, 'nickname', pr.nickname,
           'reason', s.reason, 'requested_at', s.requested_at,
           'user_country', pr.country)
         order by s.requested_at desc), '[]'::jsonb)
    into v_permits
    from public.country_send_permits s
    left join public.profiles pr on pr.id = s.uid
   where s.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', a.scope_value, 'uid', a.uid, 'nickname', pr.nickname,
           'reason', a.reason, 'created_at', a.created_at)
         order by a.created_at desc), '[]'::jsonb)
    into v_apps
    from public.moderator_applications a
    left join public.profiles pr on pr.id = a.uid
   where a.scope = 'country' and a.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', ro.country, 'room_id', ro.id,
           'message_id', r.message_id, 'reports', r.n,
           'reason_code', max(r.reason_code), 'last_at', max(r.created_at))
         order by max(r.created_at) desc), '[]'::jsonb)
    into v_reports
    from public.reports r
    join public.messages m on m.id::text = r.message_id
    join public.rooms ro on ro.id = m.room_id
   where r.message_id is not null and r.status = 'open'
   group by ro.country, ro.id, r.message_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', ro.country, 'room_id', ro.id,
           'message_id', m.id::text, 'type', m.type,
           'sender_name', m.sender_name, 'created_at', m.created_at)
         order by m.created_at desc), '[]'::jsonb)
    into v_reviews
    from public.messages m
    join public.rooms ro on ro.id = m.room_id
   where m.needs_review = true and coalesce(m.is_deleted, false) = false
   limit 100;

  return jsonb_build_object(
    'permits', v_permits,
    'applications', v_apps,
    'reports', v_reports,
    'reviews', v_reviews
  );
end;
$function$;

-- ── 11. my_moderation_state: + riwayat pencabutan (info di Profil) ────────
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
  v_revoked jsonb;
begin
  if me is null then
    return jsonb_build_object('moderates', '[]'::json, 'pending', '[]'::json,
                              'revoked', '[]'::json);
  end if;

  select coalesce(array_agg(scope_value), array[]::text[]) into v_countries
    from public.country_moderators
   where uid = me and scope = 'country' and revoked_at is null;

  select coalesce(array_agg(scope_value), array[]::text[]) into v_pending
    from public.moderator_applications
   where uid = me and scope = 'country' and status = 'pending';

  -- Pencabutan OTOMATIS karena pindah negara (untuk catatan di Profil).
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
          and ma.note = 'auto_revoke_country_change'
     )
   limit 5;

  return jsonb_build_object('moderates', to_jsonb(v_countries),
                            'pending', to_jsonb(v_pending),
                            'revoked', v_revoked);
end;
$function$;
