-- Expert selalu jawab: SoftwareExpert & HardwareExpert tidak disamakan
-- dengan AI lain — pesan ke mereka harus SELALU dibalas.
--
-- 1) Kolom baru dummy_accounts.ai_always_reply (default false) + set true
--    untuk kedua expert (by nickname, case-insensitive).
-- 2) admin_list_dummies: expose flag (debugging/admin).
--
-- Konsumen: edge function ai-reply — bila true, lewati semua penyebab
-- diam ala-personality: rate-limit per-chat (+jeda), ngambek/storm,
-- tidur & jumatan, cap AI↔AI. Kontrol admin tetap dihormati:
-- ai_enabled=false, global off, sesi dipegang, anti-race claim.

alter table public.dummy_accounts
  add column if not exists ai_always_reply boolean not null default false;

update public.dummy_accounts
   set ai_always_reply = true
 where lower(nickname) in ('softwareexpert', 'hardwareexpert');

create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows jsonb[];
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
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
    'ai_enabled', d.ai_enabled,
    'ai_persona', d.ai_persona,
    'ai_model', d.ai_model,
    'ai_guard_enabled', d.ai_guard_enabled,
    'ai_active_hours', coalesce(d.ai_active_hours, '[]'::jsonb),
    'ai_schedule_date', d.ai_schedule_date,
    'ai_schedule_auto', coalesce(d.ai_schedule_auto, true),
    'ai_no_rate_limit', coalesce(d.ai_no_rate_limit, false),
    'ai_max_replies', d.ai_max_replies,
    'ai_min_interval', d.ai_min_interval,
    'ai_always_reply', coalesce(d.ai_always_reply, false)
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;
revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;
