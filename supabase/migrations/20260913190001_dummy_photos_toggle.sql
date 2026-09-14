-- Toggle kirim foto per dummy: admin bisa mematikan kemampuan kirim
-- foto/gambar/selfie dari AI. Saat OFF:
--   - persona.no_images = true → gate line 3091 sudah ada
--   - prompt "KIRIM GAMBAR" diganti jadi "tidak bisa kirim foto"
-- Kolom: ai_photos_enabled (boolean, default true).
-- Lewat default = AI bebas kirim foto seperti sebelumnya.

alter table public.dummy_accounts
  add column if not exists ai_photos_enabled boolean default true;

-- Drop overload terbaru sebelum rebuild (hindari ambigu signature).
drop function if exists public.admin_set_dummy_ai(
  uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb, text
);

create or replace function public.admin_set_dummy_ai(
  p_uid uuid,
  p_enabled boolean,
  p_persona jsonb default '{}'::jsonb,
  p_schedule_auto boolean default null,
  p_guard_enabled boolean default null,
  p_max_replies int default null,
  p_min_interval int default null,
  p_no_rate_limit boolean default null,
  p_active_hours jsonb default null,
  p_model text default null,
  p_photos_enabled boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts where uid = p_uid) then
    raise exception 'dummy_not_found';
  end if;
  update public.dummy_accounts
  set ai_enabled = p_enabled,
      ai_persona = coalesce(p_persona, '{}'::jsonb),
      ai_schedule_auto = coalesce(p_schedule_auto, ai_schedule_auto),
      ai_guard_enabled = p_guard_enabled,
      ai_max_replies = p_max_replies,
      ai_min_interval = p_min_interval,
      ai_no_rate_limit = coalesce(p_no_rate_limit, ai_no_rate_limit),
      ai_active_hours = coalesce(p_active_hours, ai_active_hours),
      ai_photos_enabled = coalesce(p_photos_enabled, ai_photos_enabled),
      ai_model = case
        when p_model is null or p_model = '' then ai_model
        when upper(p_model) = 'NULL' then null
        else p_model
      end
  where uid = p_uid;
  return jsonb_build_object('ok', true, 'uid', p_uid, 'ai_enabled', p_enabled);
end;
$$;

revoke execute on function public.admin_set_dummy_ai(
  uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb, text, boolean
) from public, anon;
grant execute on function public.admin_set_dummy_ai(
  uuid, boolean, jsonb, boolean, boolean, int, int, boolean, jsonb, text, boolean
) to authenticated, service_role;

-- admin_list_dummies: sertakan ai_photos_enabled.
drop function if exists public.admin_list_dummies();
create or replace function public.admin_list_dummies()
returns jsonb[]
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
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
    'unread', coalesce((
      select sum(coalesce((c.unread_counts ->> d.uid::text)::int, 0))
      from public.private_chats c
      where d.uid = any (c.participants)
    ), 0),
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
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$function$;
