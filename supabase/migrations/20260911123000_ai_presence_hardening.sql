-- ============================================================
-- HARDENING AI presence (temuan review pasca-implementasi):
--   1. admin_ai_autoschedule: belum ada guard email admin (fungsi
--      admin_* lain menolak non-admin) → tambahkan.
--   2. ai_presence_tick: satu array ai_active_hours korup (non-numerik)
--      akan menggagalkan SELURUH tick (exception membatalkan loop).
--      → filter elemen non-numerik + EXCEPTION per dummy.
-- ============================================================

create or replace function public.admin_ai_autoschedule(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_hours jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if not exists (select 1 from public.dummy_accounts d where d.uid = p_uid) then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(hr order by hr), '[]'::jsonb)
  into v_hours
  from (
    select extract(hour from (m.created_at + interval '7 hours'))::int as hr
    from public.private_messages m
    where m.sender_id = p_uid
      and m.created_at > now() - interval '14 days'
      and coalesce(m.type, 'text') = 'text'
    group by hr
    having count(*) >= 2
  ) s;

  -- Fallback: kebiasaan kosong/minim → pakai jam aktif generik 8-23.
  if v_hours is null or jsonb_array_length(v_hours) < 6 then
    v_hours := '[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]'::jsonb;
  end if;

  update public.dummy_accounts
     set ai_active_hours = v_hours
   where uid = p_uid;

  return jsonb_build_object('hours', v_hours);
end;
$fn$;

revoke execute on function public.admin_ai_autoschedule(uuid) from public, anon;
grant execute on function public.admin_ai_autoschedule(uuid) to authenticated, service_role;

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
    select da.uid, da.ai_active_hours, p.status as cur_status
    from public.dummy_accounts da
    join public.profiles p on p.id = da.uid
    where da.ai_enabled = true
  loop
    begin
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
      elsif v_active and d.cur_status in ('online', 'idle') then
        -- Jaga last_seen segar supaya tetap muncul di daftar online (window 30m).
        update public.profiles set last_seen = now() where id = d.uid;
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
