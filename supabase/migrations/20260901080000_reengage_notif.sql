-- ============================================================
-- Notifikasi pengingat harian (re-engagement)
-- Target: user offline 1-8 hari (berhenti setelah 7 hari notif),
-- 1x/hari per user (dedupe last_reengage_at), admin global toggle
-- app_settings.reengage_enabled. Kirim via edge function send-push
-- (notification block — tampil walau app dimatikan).
-- Cron: 0 12 * * * (12:00 UTC = 19:00 WIB).
-- ============================================================

alter table public.app_settings
  add column if not exists reengage_enabled boolean not null default true;

alter table public.profiles
  add column if not exists last_reengage_at timestamptz;

create or replace function public.send_reengage_notifications(p_batch int default 400)
returns int language plpgsql security definer set search_path = public as $$
declare
  enabled boolean;
  rec record;
  sent int := 0;
  day_no int;
  body_id text;
  body_en text;
begin
  select reengage_enabled into enabled from app_settings where id = 'global';
  if enabled is not true then
    return 0;
  end if;

  for rec in
    select p.id, p.nickname, d.fcm_token,
           case when p.last_seen is null then 1
                else greatest(1, extract(day from (now() - p.last_seen))::int) end as offline_days
    from profiles p
    join user_devices d on d.user_id = p.id
      and d.is_active = true
      and d.fcm_token is not null and d.fcm_token <> ''
    where p.status <> 'online'
      and p.last_seen < now() - interval '1 day'
      and p.last_seen >= now() - interval '8 days'
      and (p.last_reengage_at is null or p.last_reengage_at < now() - interval '20 hours')
    order by p.last_seen desc
    limit least(greatest(coalesce(p_batch, 400), 1), 1000)
  loop
    day_no := ((rec.offline_days - 1) % 3) + 1;
    case day_no
      when 1 then begin
        body_id := '👀 Ada obrolan seru yang nungguin kamu di ChatYuk!';
        body_en := '👀 Fun chats are waiting for you on ChatYuk!';
      end;
      when 2 then begin
        body_id := '🔥 Room-nya rame lagi — yuk gabung di ChatYuk!';
        body_en := '🔥 Rooms are getting busy — join us on ChatYuk!';
      end;
      else begin
        body_id := '💬 Teman-temanmu aktif lagi, yuk buka ChatYuk!';
        body_en := '💬 Your friends are active again — open ChatYuk!';
      end;
    end case;

    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'token', rec.fcm_token,
        'title', 'ChatYuk',
        'body', body_id,
        'data', jsonb_build_object(
          'type', 'reengage'
        )
      )
    );
    sent := sent + 1;

    update profiles set last_reengage_at = now() where id = rec.id;
  end loop;
  return sent;
end; $$;

revoke execute on function public.send_reengage_notifications(int) from public, anon;
grant execute on function public.send_reengage_notifications(int) to service_role, postgres;

-- Sertakan reengage_enabled ke admin get/update settings
create or replace function public.admin_get_point_settings()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_get_point_settings() from public, anon;
grant execute on function public.admin_get_point_settings() to authenticated, service_role;

create or replace function public.admin_update_point_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    reengage_enabled      = coalesce((p->>'reengage_enabled')::boolean, reengage_enabled),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_update_point_settings(jsonb) from public, anon;
grant execute on function public.admin_update_point_settings(jsonb) to authenticated, service_role;

-- Cron: 12:00 UTC = 19:00 WIB
select cron.schedule('reengage-daily', '0 12 * * *', $$select public.send_reengage_notifications(400)$$)
where not exists (select 1 from cron.job where jobname = 'reengage-daily');
