-- ============================================================
-- AI buat jadwal kehadirannya SENDIRI tiap hari
--
-- Model: default presence dummy mengikuti kontrol manual (chip
-- Online/Idle/Offline di panel = akun biasa). Tapi saat mode AI aktif
-- + ai_schedule_auto, AI menentukan sendiri jam onlinenya SETIAP HARI
-- (disimpan ke ai_active_hours + ai_schedule_date) sehingga cronjob
-- ai_presence_tick menyalakan/mematikan sesuai keputusan AI.
-- ai_schedule_auto=false → AI tidak menyentuh jadwal (manual penuh).
-- ============================================================

alter table public.dummy_accounts
  add column if not exists ai_schedule_date date,
  add column if not exists ai_schedule_auto boolean not null default true;

-- admin_set_dummy_ai + param opsional p_schedule_auto (null = tidak diubah).
create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb,
  p_schedule_auto boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts where uid = p_uid) then
    raise exception 'dummy_not_found';
  end if;
  update public.dummy_accounts
  set ai_enabled = p_enabled,
      ai_persona = coalesce(p_persona, '{}'::jsonb),
      ai_schedule_auto = coalesce(p_schedule_auto, ai_schedule_auto)
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;

revoke execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean) from public, anon;
grant execute on function public.admin_set_dummy_ai(uuid, boolean, jsonb, boolean) to authenticated, service_role;

-- admin_list_dummies: sertakan mode + tanggal jadwal (sheet AI).
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
