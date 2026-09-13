-- Restore ai_always_online di ai_presence_tick (khusus Admin Chatyuk).
--
-- Akar: 20260913070000 menambah cabang always_online, tapi 20260913150000
-- (invisible) + 20260913180000 (wake) redefine tick TANPA cabang itu,
-- sehingga Admin Chatyuk ikut jadwal tidur → offline mulu.
--
-- Fix SURGICAL: copy persis tick 20260913180000, hanya tambah:
--   1) da.ai_always_online di SELECT,
--   2) satu blok IF always_online setelah ngambek, sebelum cek jadwal.
-- Alur lain (invisible, wake, ngambek, jadwal, idle-drift) TIDAK DIUBAH
-- byte-per-byte — dummy selain flagged jalurnya identik seperti sebelumnya.
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
  v_wake bool;
begin
  v_hour := extract(hour from (now() + interval '7 hours'))::int;

  for d in
    select da.uid, da.ai_active_hours, da.ai_offline_until, da.ai_wake_until,
           da.ai_always_online, p.status as cur_status
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
      -- ── BANGUNKAN SEMENTARA (admin_wake_dummy): paksa online + segar
      -- sampai ai_wake_until lewat. Mengalahkan jadwal & tidur.
      v_wake := d.ai_wake_until is not null and d.ai_wake_until > now();
      if v_wake then
        if d.cur_status <> 'online' then
          update public.profiles
             set status = 'online', last_seen = now()
           where id = d.uid;
        else
          update public.profiles set last_seen = now() where id = d.uid;
        end if;
        continue;
      end if;
      -- Wake kedaluwarsa → bersihkan sekali (jadwal di bawah mengambil alih).
      if d.ai_wake_until is not null then
        update public.dummy_accounts set ai_wake_until = null where uid = d.uid;
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

      -- ── SELALU ONLINE (cabang restore 13070000; hanya Admin Chatyuk
      -- yang flag-nya true) — jadwal & idle-drift dilewati: paksa online
      -- + last_seen segar. Dummy lain (false) lewat sini tanpa perubahan.
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

-- DATA (hanya Admin Chatyuk, dummy lain TIDAK disentuh):
-- always_online = presence 24 jam; no_sleep = ai-reply tidak kena gate tidur.
update public.dummy_accounts d
   set ai_enabled = true,
       ai_always_online = true,
       ai_no_sleep = true,
       ai_offline_until = null,
       ai_wake_until = null
  from public.profiles p
 where p.id = d.uid
   and p.nickname ilike '%admin%chatyuk%';

update public.profiles p
   set status = 'online', last_seen = now()
  from public.dummy_accounts d
 where p.id = d.uid
   and p.nickname ilike '%admin%chatyuk%';
