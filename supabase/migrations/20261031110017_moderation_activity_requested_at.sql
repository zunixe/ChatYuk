-- Fix admin_moderation_activity: kolom moderator_applications adalah
-- created_at (bukan requested_at) — fungsi live error "column requested_at
-- does not exist" sejak migrasi 20261027160000. Ditangkap oleh
-- moderator_slots_test.sql. Body diambil dari live (pg_get_functiondef)
-- dan hanya 1 baris diubah. country_send_permits.requested_at BENAR ada
-- di skema — dibiarkan.
create or replace function public.admin_moderation_activity()
 returns jsonb
 language plpgsql
 stable security definer
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
    'applications', (select count(*) from public.moderator_applications
                      where status = 'pending'),
    'applications_at', (select max(created_at)
                          from public.moderator_applications
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
