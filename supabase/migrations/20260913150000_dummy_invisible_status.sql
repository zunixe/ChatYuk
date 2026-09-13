-- Dummy invisible: dummy bisa diset status 'invisible' (user lain lihat
-- offline, tidak muncul di daftar online — chat_service sudah memetakan
-- invisible→offline & memfilternya; tinggal RPC + cron yang disesuaikan).
--
-- 1) admin_set_dummy_status: izinkan 'invisible' + guard modern
--    is_admin_request() (pengganti cek auth.email() lama yang gagal saat
--    JWT tanpa claim email).
-- 2) ai_presence_tick: JANGAN sentuh dummy berstatus 'invisible' —
--    itu pilihan manual admin, bukan drift presence alami.

create or replace function public.admin_set_dummy_status(p_uid uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  if p_status not in ('online', 'idle', 'offline', 'invisible') then
    raise exception 'Status tidak valid';
  end if;
  update public.profiles
     set status = p_status, last_seen = now()
   where id = p_uid;
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.admin_set_dummy_status(uuid, text) from public, anon;
grant execute on function public.admin_set_dummy_status(uuid, text) to authenticated, service_role;

-- ai_presence_tick: lewati dummy invisible (pilihan manual admin).
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
    select da.uid, da.ai_active_hours, da.ai_offline_until, p.status as cur_status
    from public.dummy_accounts da
    join public.profiles p on p.id = da.uid
    where da.ai_enabled = true
  loop
    begin
      -- Invisible manual (set dari admin panel) — cron tidak boleh
      -- menimpa (baik membangunkan saat jam aktif maupun meng-offline-kan
      -- di luar jam). AI tetap membalas; presence-wake ai-reply juga
      -- mempertahankan status ini (cabang else = refresh last_seen saja).
      if d.cur_status = 'invisible' then
        continue;
      end if;
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
