-- TINJAUAN MEDIA (verdict 'review') + konsol moderasi lebih lengkap.
--
-- 1. `messages.needs_review` — pesan yang lolos kirim tetapi skor NSFW
--    borderline (0.50–0.75) sehingga WAJIB ditinjau moderator. Sebelumnya
--    verdict 'review' diabaikan (tidak ada jejak).
-- 2. RPC `flag_media_review` — dipanggil pengirim setelah pesan terkirim.
-- 3. `moderator_console` & `admin_moderation_overview` diperluas:
--    - daftar `reviews` (pesan menunggu tinjauan)
--    - laporan menyertakan `type`, `image_path`, `text`, `hidden` agar
--      moderator bisa MELIHAT media yang dilaporkan tanpa mencari manual.
-- 4. RPC `admin_search_users` — admin bisa mengangkat moderator di luar
--    daftar kandidat.
--
-- SAFE: 1 kolom aditif (nullable/default false) + RPC baru/`create or replace`
--       milik fitur ini. Tidak menyentuh policy/RLS tabel bersama.
alter table public.messages
  add column if not exists needs_review boolean not null default false;

create index if not exists messages_needs_review_idx
  on public.messages (needs_review) where needs_review = true;

-- ── Pengirim menandai pesannya butuh tinjauan ──────────────────────────────
create or replace function public.flag_media_review(p_message_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  update public.messages
     set needs_review = true
   where id::text = p_message_id
     and sender_id = me;

  return jsonb_build_object('ok', found);
end;
$function$;

revoke execute on function public.flag_media_review(text) from public, anon;
grant execute on function public.flag_media_review(text) to authenticated;

-- ── Konsol per negara (versi lengkap) ──────────────────────────────────────
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
  v_reviews jsonb;
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
           'created_at', a.created_at, 'nickname', pr.nickname)
         order by a.created_at desc), '[]'::jsonb)
    into v_apps
    from public.moderator_applications a
    left join public.profiles pr on pr.id = a.uid
   where a.scope = 'country' and a.scope_value = p_country
     and a.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'uid', s.uid, 'status', s.status, 'reason', s.reason,
           'requested_at', s.requested_at, 'nickname', pr.nickname)
         order by s.requested_at desc), '[]'::jsonb)
    into v_permits
    from public.country_send_permits s
    left join public.profiles pr on pr.id = s.uid
   where s.country = p_country and s.status = 'pending';

  -- Laporan: sertakan tipe/path/teks + status sembunyi agar UI bisa
  -- menampilkan thumbnail dan membatalkan penyembunyian.
  select coalesce(jsonb_agg(jsonb_build_object(
           'message_id', r.message_id,
           'reports', r.n,
           'room_id', max(r.room_id),
           'reason_code', max(r.reason_code),
           'last_at', max(r.created_at),
           'type', max(m.type),
           'image_path', max(coalesce(m.image_path, '')),
           'text', left(max(coalesce(m.text, '')), 120),
           'hidden', bool_or(coalesce(m.is_deleted, false)))
         order by max(r.created_at) desc), '[]'::jsonb)
    into v_reports
    from public.reports r
    join public.messages m on m.id::text = r.message_id
    join public.rooms ro on ro.id = m.room_id
   where r.message_id is not null and r.status = 'open'
     and ro.country = p_country
   group by r.message_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'message_id', m.id::text,
           'room_id', m.room_id,
           'type', m.type,
           'image_path', coalesce(m.image_path, ''),
           'text', left(coalesce(m.text, ''), 120),
           'created_at', m.created_at,
           'sender_name', m.sender_name)
         order by m.created_at desc), '[]'::jsonb)
    into v_reviews
    from public.messages m
    join public.rooms ro on ro.id = m.room_id
   where m.needs_review = true
     and ro.country = p_country
     and coalesce(m.is_deleted, false) = false
   limit 100;

  select coalesce(jsonb_agg(jsonb_build_object(
           'uid', cm.uid, 'granted_at', cm.granted_at,
           'nickname', pr.nickname, 'source', cm.source)
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
    'reviews', v_reviews,
    'moderators', v_mods
  );
end;
$function$;

-- ── Ringkasan lintas negara untuk admin (tambah `reviews`) ─────────────────
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
           'home_country', prof.home_country)
         order by s.requested_at desc), '[]'::jsonb)
    into v_permits
    from public.country_send_permits s
    left join public.profiles pr on pr.id = s.uid
    left join public.profiles prof on prof.id = s.uid
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

-- ── Admin mencari user untuk diangkat jadi moderator ───────────────────────
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
             'home_country', p.home_country,
             'messages', (select count(*) from public.messages m
                          where m.sender_id = p.id))
           order by p.nickname)
      from (
        select pr.id, pr.nickname, pr.home_country
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
