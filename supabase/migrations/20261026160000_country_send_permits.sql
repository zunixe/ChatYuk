-- IZIN KIRIM MEDIA LINTAS NEGARA (permintaan user 2026-10-26)
--
-- ATURAN:
--   * Room publik negara SENDIRI (profiles.home_country) → cukup trust gate.
--   * Room publik negara LAIN → WAJIB punya izin `approved` untuk negara itu
--     (permanen selama tidak melanggar; bisa dicabut moderator/admin).
--   * Room privat/grup → tidak berubah.
--   * Teks/voice/lokasi → tidak dibatasi.
--
-- Siapa yang menyetujui: moderator negara tujuan; bila belum ada moderator,
-- permohonan masuk antrean ADMIN (status tetap pending, terlihat di daftar
-- permohonan karena RLS mengizinkan admin membaca semua baris).
--
-- SAFE: tabel baru + fungsi baru + `create or replace` pada
--       `can_send_room_media` (fungsi milik fitur ini, bukan FROZEN).
--       Tidak menyentuh policy/RLS tabel yang sudah ada.
--       Fitur terdampak: kirim media di room publik lintas negara.

create table if not exists public.country_send_permits (
  id           bigserial primary key,
  uid          uuid not null references auth.users(id) on delete cascade,
  country      text not null,
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'rejected', 'revoked')),
  reason       text not null default '',
  requested_at timestamptz not null default now(),
  decided_by   uuid,
  decided_at   timestamptz,
  decision_note text,
  unique (uid, country)
);

create index if not exists country_send_permits_country_idx
  on public.country_send_permits (country, status);

alter table public.country_send_permits enable row level security;

-- Pemohon melihat izinnya sendiri; moderator negara & admin melihat semua
-- permohonan di negaranya.
-- SAFE: policy SELECT aditif pada tabel BARU; tidak menyentuh tabel lain.
create policy country_send_permits_select on public.country_send_permits -- SAFE: SELECT sendiri / moderator negara / admin; tabel baru, tidak ada data sensitif.
  for select to authenticated
  using (
    uid = auth.uid()
    or public.is_chatyuk_admin(auth.uid())
    or public.is_country_moderator(country, auth.uid())
  );

grant select on public.country_send_permits to authenticated; -- SAFE: baca tabel baru; RLS membatasi ke pemohon/moderator/admin.

-- ── Permohonan izin ────────────────────────────────────────────────────────
create or replace function public.request_country_permit(
  p_country text,
  p_reason  text default ''
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

  select home_country into v_home from public.profiles where id = me;
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

revoke execute on function public.request_country_permit(text, text) from public, anon;
grant execute on function public.request_country_permit(text, text) to authenticated;

-- ── Keputusan moderator negara / admin ────────────────────────────────────
create or replace function public.decide_country_permit(
  p_uid     uuid,
  p_country text,
  p_approve boolean,
  p_note    text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me  uuid := auth.uid();
  ok  boolean;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  ok := public.is_chatyuk_admin(me)
     or public.is_country_moderator(p_country, me);
  if not ok then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.country_send_permits
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = me,
         decided_at = now(),
         decision_note = coalesce(p_note, '')
   where uid = p_uid and country = p_country;

  if not found then
    raise exception 'permit_not_found' using errcode = 'P0002';
  end if;

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', p_country, me, p_uid,
          case when p_approve then 'grant_permit' else 'revoke_permit' end,
          coalesce(p_note, ''));

  return jsonb_build_object('ok', true, 'approved', p_approve);
end;
$function$;

revoke execute on function public.decide_country_permit(uuid, text, boolean, text) from public, anon;
grant execute on function public.decide_country_permit(uuid, text, boolean, text) to authenticated;

-- ── Cabut izin (melanggar) ────────────────────────────────────────────────
create or replace function public.revoke_country_permit(
  p_uid     uuid,
  p_country text,
  p_reason  text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
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

  update public.country_send_permits
     set status = 'revoked', decided_by = me, decided_at = now(),
         decision_note = coalesce(p_reason, '')
   where uid = p_uid and country = p_country;

  insert into public.moderator_actions
    (scope, scope_value, uid, target_uid, action, note)
  values ('country', p_country, me, p_uid, 'revoke_permit',
          coalesce(p_reason, ''));

  return jsonb_build_object('ok', true);
end;
$function$;

revoke execute on function public.revoke_country_permit(uuid, text, text) from public, anon;
grant execute on function public.revoke_country_permit(uuid, text, text) to authenticated;

-- ── Gate: tambahkan syarat izin lintas negara ─────────────────────────────
create or replace function public.can_send_room_media(
  p_room text,   -- rooms.id / messages.room_id bertipe TEXT
  p_uid  uuid
)
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

  select r.is_private, r.country
    into v_private, v_country
    from public.rooms r
   where r.id = p_room;

  if v_private is null then
    return false;
  end if;

  -- Room privat: perilaku lama, bebas.
  if v_private then
    return true;
  end if;

  -- Admin global & moderator negara room tsb: bypass.
  if public.is_chatyuk_admin(p_uid) then
    return true;
  end if;
  if public.is_country_moderator(v_country, p_uid) then
    return true;
  end if;

  -- LINTAS NEGARA: home_country beda dengan negara room → wajib izin approved.
  select home_country into v_home from public.profiles where id = p_uid;
  if coalesce(v_home, '') <> '' and v_home <> coalesce(v_country, '') then
    if not exists (
      select 1 from public.country_send_permits p
       where p.uid = p_uid
         and p.country = v_country
         and p.status = 'approved'
    ) then
      return false;
    end if;
  end if;

  select coalesce(media_trust_min_days, 3),
         coalesce(media_trust_min_msgs, 20)
    into v_min_days, v_min_msgs
    from public.app_settings where id = 'global';

  select p.created_at into v_created
    from public.profiles p where p.id = p_uid;
  if v_created is null then
    return false;
  end if;
  if v_created > now() - make_interval(days => v_min_days) then
    return false;
  end if;

  select count(*)
    into v_msgs
    from public.messages m
    join public.rooms r2 on r2.id = m.room_id
   where m.sender_id = p_uid
     and r2.is_private = false;

  return v_msgs >= v_min_msgs;
end;
$function$;
