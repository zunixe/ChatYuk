-- DAFTAR MODERASI GABUNGAN untuk ADMIN (semua negara dalam satu tampilan).
--
-- Masalah: `moderator_console(country)` hanya mengembalikan data SATU negara,
-- sehingga admin harus menebak negara mana yang punya permohonan izin
-- lintas negara / laporan / lamaran moderator.
--
-- Fungsi ini mengembalikan SEMUA yang menunggu tinjauan, dikelompokkan per
-- negara, khusus admin global (is_chatyuk_admin).
--
-- SAFE: fungsi baru read-only; tidak mengubah policy/tabel.
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
begin
  if not public.is_chatyuk_admin(me) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', s.country,
           'uid', s.uid,
           'nickname', pr.nickname,
           'reason', s.reason,
           'requested_at', s.requested_at,
           'home_country', prof.home_country)
         order by s.requested_at desc), '[]'::jsonb)
    into v_permits
    from public.country_send_permits s
    left join public.profiles pr on pr.id = s.uid
    left join public.profiles prof on prof.id = s.uid
   where s.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', a.scope_value,
           'uid', a.uid,
           'nickname', pr.nickname,
           'reason', a.reason,
           'created_at', a.created_at)
         order by a.created_at desc), '[]'::jsonb)
    into v_apps
    from public.moderator_applications a
    left join public.profiles pr on pr.id = a.uid
   where a.scope = 'country' and a.status = 'pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'country', ro.country,
           'room_id', ro.id,
           'message_id', r.message_id,
           'reports', r.n,
           'reason_code', max(r.reason_code),
           'last_at', max(r.created_at))
         order by max(r.created_at) desc), '[]'::jsonb)
    into v_reports
    from public.reports r
    join public.messages m on m.id::text = r.message_id
    join public.rooms ro on ro.id = m.room_id
   where r.message_id is not null and r.status = 'open'
   group by ro.country, ro.id, r.message_id;

  return jsonb_build_object(
    'permits', v_permits,
    'applications', v_apps,
    'reports', v_reports
  );
end;
$function$;

revoke execute on function public.admin_moderation_overview() from public, anon;
grant execute on function public.admin_moderation_overview() to authenticated;
