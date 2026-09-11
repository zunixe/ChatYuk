-- ============================================================
-- Emosi dummy yang menempel + ngambek pergi offline
--
-- Permintaan owner:
--   - Tugas AI: membangun ikatan emosi lawan chat sampai menempel.
--   - Ketika MARAH dan "mau off": benar-benar offline (tidak membalas
--     sama sekali), lalu cron yang menyalakan kembali nanti.
--
-- Implementasi:
--   - dummy_accounts.ai_mood: mood terakhir (happy/normal/annoyed/sad)
--     — dipertahankan lintas invokasi supaya emosi menempel.
--   - dummy_accounts.ai_offline_until: timestamptz — selama now() <
--     nilai ini dummy dipaksa OFFLINE (ai-reply skip, tick paksa offline);
--     lewat waktu → tick menyalakan kembali sesuai jadwal jam aktif.
--   - Edge function: LLM output marker mood JSON di baris terakhir →
--     di-strip sebelum insert, disimpan di sini.
-- ============================================================

alter table public.dummy_accounts
  add column if not exists ai_mood text not null default 'normal',
  add column if not exists ai_offline_until timestamptz;

-- ai_presence_tick: hormati ai_offline_until (marah mode).
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
