-- ============================================================
-- Akun dummy "selalu online" 24 jam (pengecualian, mis. Admin Chatyuk)
--
-- Permintaan owner: Admin Chatyuk (akun resmi) tetap online 24 jam,
-- dummy lain ikut siklus natural (online→idle→off + jeda siang).
--
--   - dummy_accounts.ai_always_online: true → tick memaksa status
--     online + last_seen segar tiap 5 menit (jadwal & idle-drift
--     dilewati; mode ngambek tetap dihormati sebagai katup pengaman).
--   - admin_list_dummies: sertakan flag (siap untuk toggle di panel).
-- ============================================================

alter table public.dummy_accounts
  add column if not exists ai_always_online boolean not null default false;

create or replace function public.ai_presence_tick()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  d record;
  v_hour int;
  v_active bool;
begin
  v_hour := extract(hour from (now() + interval '7 hours'))::int;

  for d in
    select da.uid, da.ai_active_hours, da.ai_offline_until,
           da.ai_always_online, p.status as cur_status
    from public.dummy_accounts da
    join public.profiles p on p.id = da.uid
    where da.ai_enabled = true
  loop
    begin
      -- ── MODE NGAMBEK (marah pergi) ──
      if d.ai_offline_until is not null and d.ai_offline_until > now() then
        if d.cur_status <> 'offline' then
          update public.profiles
             set status = 'offline', last_seen = now()
           where id = d.uid;
        end if;
        continue; -- abaikan jadwal jam aktif selama ngambek
      end if;
      -- Waktu ngambek habis → bangunkan sesuai jadwal.
      if d.ai_offline_until is not null and d.ai_offline_until <= now() then
        update public.dummy_accounts set ai_offline_until = null, ai_mood = 'normal'
          where uid = d.uid;
        update public.profiles
           set status = (case when v_hour::int = any(
                 select (x::int) from jsonb_array_elements_text(
                   coalesce(d.ai_active_hours, '[]'::jsonb)) as x
                 where x ~ '^[0-9]+$'
               ) then 'online' else 'offline' end),
               last_seen = now()
         where id = d.uid;
        continue;
      end if;

      -- ── SELALU ONLINE (akun resmi) ──
      -- Jadwal & idle-drift dilewati: paksa online + last_seen segar.
      if coalesce(d.ai_always_online, false) then
        if d.cur_status <> 'online' then
          update public.profiles
             set status = 'online', last_seen = now()
           where id = d.uid;
        else
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
        continue;
      end if;

      -- Jadwal belum diatur → jangan sentuh presence (mode manual).
      if d.ai_active_hours is null or
         jsonb_array_length(d.ai_active_hours) = 0 then
        continue;
      end if;

      -- Hanya elemen numerik yang dipakai (array korup tidak boleh
      -- menggagalkan tick untuk dummy lain).
      v_active := (v_hour::int = any(
        select (x::int)
        from jsonb_array_elements_text(d.ai_active_hours) as x
        where x ~ '^[0-9]+$'
      ));

      if v_active and d.cur_status = 'offline' then
        update public.profiles
           set status = 'online', last_seen = now()
         where id = d.uid;
      elsif v_active and d.cur_status = 'online' then
        -- Kadang melamun seperti user mendiamkan app: 30%/tick → idle.
        if random() < 0.30 then
          update public.profiles
             set status = 'idle', last_seen = now()
           where id = d.uid;
        else
          -- Jaga last_seen segar supaya tetap muncul di daftar online (window 30m).
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
      elsif v_active and d.cur_status = 'idle' then
        -- Kembali pegang HP: 50%/tick → online. last_seen selalu segar
        -- supaya idle tetap tampil di daftar online.
        if random() < 0.50 then
          update public.profiles
             set status = 'online', last_seen = now()
           where id = d.uid;
        else
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
      elsif not v_active and d.cur_status <> 'offline' then
        update public.profiles set status = 'offline' where id = d.uid;
      end if;
    exception when others then
      -- Satu dummy bermasalah tidak boleh menghentikan tick dummy lain.
      continue;
    end;
  end loop;
end;
$fn$;

revoke execute on function public.ai_presence_tick() from public, anon;
grant execute on function public.ai_presence_tick() to service_role;

-- admin_list_dummies: sertakan flag always-online.
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
    'ai_min_interval', d.ai_min_interval
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$$;

revoke execute on function public.admin_list_dummies() from public, anon;
grant execute on function public.admin_list_dummies() to authenticated, service_role;
