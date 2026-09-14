-- menyentuh: admin_list_dummies
-- Tahap 2 audit performa: `admin_list_dummies()` mengembalikan SELURUH tabel
-- dummy tanpa limit dan dipanggil tiap 30 dtk oleh admin panel → payload
-- besar berulang. Tambah varian ber-paginasi `admin_list_dummies_page`.
--
-- PENTING (kompatibilitas): `admin_list_dummies()` (tanpa argumen) TIDAK
-- diubah — masih dipakai jalur lama. Fungsi baru ini murni tambahan.
create or replace function public.admin_list_dummies_page(
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_items jsonb[];
  v_total int;
  v_limit int := greatest(1, least(coalesce(p_limit, 50), 200));
  v_offset int := greatest(0, coalesce(p_offset, 0));
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;

  select count(*) into v_total from public.dummy_accounts;

  select coalesce(array_agg(jsonb_build_object(
    'uid', d.uid,
    'nickname', p.nickname,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'gender', p.gender,
    'age', p.age,
    'city', p.city,
    'country', p.country,
    'unread', coalesce((
      select sum(coalesce((c.unread_counts ->> d.uid::text)::int, 0))
      from public.private_chats c
      where d.uid = any (c.participants)
    ), 0),
    'kind', coalesce(d.kind, 'regular'),
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_guard_enabled', d.ai_guard_enabled,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true),
    'ai_always_online', coalesce(d.ai_always_online, false),
    'ai_no_rate_limit', coalesce(d.ai_no_rate_limit, false),
    'ai_max_replies', d.ai_max_replies,
    'ai_min_interval', d.ai_min_interval,
    'ai_always_reply', coalesce(d.ai_always_reply, false),
    'ai_wake_until', d.ai_wake_until,
    'ai_photos_enabled', coalesce(d.ai_photos_enabled, true)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_items
  from (
    select * from public.dummy_accounts
    order by created_at desc
    limit v_limit offset v_offset
  ) d
  join public.profiles p on p.id = d.uid;

  return jsonb_build_object(
    'items', coalesce(v_items, '{}'::jsonb[]),
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset
  );
end;
$function$;

revoke execute on function public.admin_list_dummies_page(int, int) from public, anon;
grant execute on function public.admin_list_dummies_page(int, int) to authenticated, service_role;
