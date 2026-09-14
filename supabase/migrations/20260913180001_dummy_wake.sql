-- Fitur Bangunkan 10 menit (admin panel kartu dummy).
--
-- Masalah: dummy tidur (gate asleepAt 20-23→04-06) tapi owner butuh
-- membangunkan SEMENTARA untuk testing — ai_no_sleep permanen, terlalu
-- kasar. Kolom ai_wake_until = paksa melek sampai waktu tsb:
--   - gate balasan ai-reply melewati cek tidur selama wake aktif,
--   - ai_presence_tick memaksa online + last_seen segar selama wake aktif,
--   - lewat masa → kembali normal otomatis (jadwal + tidur biasa).
-- Konsistensi frontend: admin_list_dummies ikut mengembalikan
-- ai_wake_until; klien menghitung Tidur/Bangun + sisa waktu.

alter table public.dummy_accounts
  add column if not exists ai_wake_until timestamptz;

-- RPC: bangunkan dummy N menit (default 10). Guard admin. Presence
-- langsung online supaya konsisten di depan tanpa tunggu tick 5 mnt.
-- Invisible manual dihormati (tetap invisible, hanya wake_until di-set).
create or replace function public.admin_wake_dummy(
  p_uid uuid,
  p_minutes integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_until timestamptz;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  v_until := now() + make_interval(mins => least(greatest(coalesce(p_minutes, 10), 1), 120));
  update public.dummy_accounts
     set ai_wake_until = v_until
   where uid = p_uid;
  update public.profiles
     set status = 'online', last_seen = now()
   where id = p_uid and status <> 'invisible';
  return jsonb_build_object('uid', p_uid, 'wake_until', v_until);
end;
$fn$;

revoke execute on function public.admin_wake_dummy(uuid, integer) from public, anon;
grant execute on function public.admin_wake_dummy(uuid, integer) to authenticated, service_role;

-- Tick presence: wake aktif → paksa online (kecuali invisible manual).
-- Ditaruh SEBELUM logika jadwal; expired dibersihkan sekalian.
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
    select da.uid, da.ai_active_hours, da.ai_offline_until, da.ai_wake_until, p.status as cur_status
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

-- List dummy: sertakan ai_wake_until untuk chip Tidur/Bangun di kartu.
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
    'ai_wake_until', d.ai_wake_until
  ) order by d.created_at desc), '{}'::jsonb[])
  into v_rows
  from public.dummy_accounts d
  join public.profiles p on p.id = d.uid;
  return v_rows;
end;
$function$;
