-- admin_user_detail: batasi location_history + agregasi message_count.
--
-- SEBELUM (20260825130000):
--   - `message_count` = correlated count(*) per chat (N+1 untuk user yang
--     punya banyak chat).
--   - `location_history` TANPA limit — user aktif = ribuan baris dalam
--     1 panggilan sheet.
-- SESUDAH:
--   - message_count via 1× GROUP BY di-join ke chats user.
--   - location_history dibatasi 200 terbaru (cukup untuk sheet detail/jejak;
--     riwayat penuh tetap di tabel).
-- Kunci JSON TIDAK berubah (kompatibel dengan user_detail_sheet.dart).
-- Bukan fungsi frozen.
create or replace function public.admin_user_detail(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id',        pr.id,
      'nickname',       pr.nickname,
      'gender',         pr.gender,
      'age',            pr.age,
      'country',        pr.country,
      'city',           pr.city,
      'email',          pr.email,
      'is_registered',  pr.is_registered,
      'status',         pr.status,
      'points',         pr.points,
      'ip_address',     pr.ip_address,
      'login_at',       pr.login_at,
      'last_seen',      pr.last_seen,
      'created_at',     pr.created_at,
      'is_dummy',       exists (select 1 from public.dummy_accounts du where du.uid = pr.id)
    ),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'install_id',   d.install_id,
        'brand',        d.brand,
        'model',        d.model,
        'os_name',      d.os_name,
        'os_version',   d.os_version,
        'app_version',  d.app_version,
        'ip_address',   d.ip_address,
        'last_seen_at', d.last_seen_at,
        'is_active',    d.is_active,
        'created_at',   d.created_at
      ) order by d.last_seen_at desc nulls last)
      from public.user_devices d where d.user_id = p_uid
    ), '[]'::jsonb),
    'chats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'chat_id', c.chat_id,
        'participant_names', c.participant_names,
        'participants', c.participants,
        'last_message', c.last_message,
        'last_message_at', c.last_message_at,
        'message_count', coalesce(m.msg_count, 0)
      ) order by c.last_message_at desc nulls last)
      from public.private_chats c
      -- SATU agregasi (ganti count(*) per chat).
      left join (
        select m.chat_id as chat_id, count(*) as msg_count
          from public.private_messages m
         where m.chat_id in (
           select c2.chat_id from public.private_chats c2
           where c2.participants @> array[p_uid]::uuid[]
         )
         group by m.chat_id
      ) m on m.chat_id = c.chat_id
      where c.participants @> array[p_uid]::uuid[]
    ), '[]'::jsonb),
    -- DIBATASI 200 terbaru (dulu tanpa limit).
    'location_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lat', h.lat,
        'lon', h.lon,
        'source', h.loc_source,
        'at', h.created_at
      ) order by h.created_at desc)
      from (
        select h2.lat, h2.lon, h2.loc_source, h2.created_at
          from public.user_location_history h2
         where h2.user_id = p_uid
         order by h2.created_at desc
         limit 200
      ) h
    ), '[]'::jsonb)
  ) into result
  from public.profiles pr
  where pr.id = p_uid;

  if result is null then
    raise exception 'User not found';
  end if;
  return result;
end;
$fn$;

revoke execute on function public.admin_user_detail(uuid) from public, anon;
