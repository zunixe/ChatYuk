-- ============================================================
-- ChatYuk: admin_list_dummies + jumlah pesan belum dibaca (unread)
-- Tambah field 'unread' = total unread_counts[dummy_uid] dari semua
-- private_chats yang melibatkan dummy tsb. Dipakai di Admin Panel > Dummy
-- untuk menampilkan badge jumlah pesan masuk dari orang lain.
-- ============================================================

create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_rows jsonb[];
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'gender', p.gender,
    'age', p.age,
    'country', p.country,
    'city', p.city,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'unread', coalesce((
      select sum(coalesce((c.unread_counts ->> d.uid::text)::int, 0))
      from public.private_chats c
      where d.uid = any (c.participants)
    ), 0)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$function$;

revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;
