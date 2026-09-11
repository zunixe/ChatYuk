-- admin_list_dummies: sertakan gender/age/city — kartu dummy menampilkan
-- "gender · umur · kota" tapi RPC tidak mengirimnya → fallback 'male'
-- (semua tampil Laki-laki, umur & kota kosong).
create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path = public, extensions
as $$
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
    'city', p.city,
    'status', p.status,
    'last_seen', p.last_seen,
    'created_at', d.created_at,
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;

revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;
