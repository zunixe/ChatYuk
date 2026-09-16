-- SNAPSHOT fungsi FROZEN (auto-generate). JANGAN edit manual.
-- Regenerate: scripts/snapshot_functions.sh
-- Timestamp: 2026-09-16T13:33:07Z

-- snapshot-fn: ai_presence_tick @ 20260914020000_admin_chatyuk_always_online_restore.sql
CREATE OR REPLACE FUNCTION public.ai_presence_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

-- snapshot-fn: ai_reply_enqueue @ 20260915090000_ai_ai_chat_toggle.sql
CREATE OR REPLACE FUNCTION public.ai_reply_enqueue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_other uuid;
  v_no_rate boolean;
  v_always_reply boolean;
  v_sender_no_rate boolean;
  v_sender_is_dummy boolean;
  v_global boolean;
  v_ai_ai_on boolean;
  v_max int;
  v_min int;
  v_gmax int;
  v_gmin int;
  v_dummy_out_1h int;
  v_last_dummy_out timestamptz;
  v_ai_ai_1h int;
begin
  -- Only plain text messages
  if coalesce(new.type, 'text') != 'text' then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null, false, 'enqueue', 'skipped:non_text', '{}');
    return new;
  end if;

  select x into v_other
  from unnest(
    (select pc.participants from public.private_chats pc where pc.chat_id = new.chat_id)
  ) as x
  where x <> new.sender_id
  limit 1;
  if v_other is null then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null, false, 'enqueue', 'skipped:no_other', '{}');
    return new;
  end if;

  -- Recipient must be an AI-enabled dummy (ambil config sekalian).
  -- PENTING: pakai IF NOT FOUND (bukan cek null!) Î“Ã‡Ã¶ kolom flag boleh null.
  select d.ai_no_rate_limit, d.ai_always_reply, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_always_reply, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if not found then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:dummy_disabled', '{}');
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec,
         coalesce(s.ai_ai_chat_enabled, true)
    into v_global, v_gmax, v_gmin, v_ai_ai_on
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:global_off', '{}');
    return new;
  end if;

  -- ── TOGGLE AI↔AI: sender dummy & tombol off → dummy tidak dibalas. ──
  if v_sender_is_dummy and not coalesce(v_ai_ai_on, true) then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:ai_ai_off', '{}');
    return new;
  end if;

  -- Î“Ã¶Ã‡Î“Ã¶Ã‡ always_reply (expert/CS): LEWATI semua cap & rate. Pesan selalu enqueue.
  if coalesce(v_always_reply, false) then
    perform public.ai_reply_post(new.chat_id, new.id, new.sender_id, v_other, false);
    return new;
  end if;

  v_max := coalesce(v_max, v_gmax, 30);
  v_min := coalesce(v_min, v_gmin, 5);

  if v_sender_is_dummy then
    -- Î“Ã¶Ã‡Î“Ã¶Ã‡ AIÎ“Ã¥Ã¶AI: cap KERAS gabungan 40 pesan/jam Î“Ã‡Ã¶ KECUALI kedua dummy
    -- eksplisit no_rate_limit (unlimited by design, mis. Expertâ”œÃ¹Expert).
    select coalesce(d.ai_no_rate_limit, false) into v_sender_no_rate
    from public.dummy_accounts d where d.uid = new.sender_id;
    if not (coalesce(v_no_rate, false) and coalesce(v_sender_no_rate, false)) then
      select count(*) into v_ai_ai_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id in (v_other, new.sender_id)
        and m.created_at > now() - interval '1 hour';
      if v_ai_ai_1h >= 40 then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:ai_ai_cap', '{}');
        return new;
      end if;
    end if;
  else
    -- Î“Ã¶Ã‡Î“Ã¶Ã‡ Sender manusia: rate limit (per-dummy override Î“Ã¥Ã† global)
    if not coalesce(v_no_rate, false) then
      select count(*) into v_dummy_out_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other
        and m.created_at > now() - interval '1 hour';
      if v_dummy_out_1h >= v_max then
        -- Kuota habis Î“Ã¥Ã† tampil idle (downgrade onlineÎ“Ã¥Ã†idle saja).
        -- Exception-safe: kolom ai_always_online mungkin belum ada di DB
        -- lama; kegagalan presence TIDAK BOLEH menggagalkan insert pesan.
        begin
          begin
            perform 1 from public.dummy_accounts
              where uid = v_other and coalesce(ai_always_online, false) = true;
            if found then
              null; -- always_online: jangan sentuh presence.
            else
              update public.profiles
                 set status = 'idle', last_seen = now()
               where id = v_other and status = 'online';
            end if;
          exception when undefined_column then
            update public.profiles
               set status = 'idle', last_seen = now()
             where id = v_other and status = 'online';
          end;
        exception when others then
          null;
        end;
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:rate_max', jsonb_build_object('out_1h', v_dummy_out_1h, 'max', v_max));
        return new;
      end if;

      select max(m.created_at) into v_last_dummy_out
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other;
      if v_last_dummy_out is not null
         and v_last_dummy_out > now() - make_interval(secs => v_min) then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:rate_min_interval', '{}');
        return new;
      end if;
    end if;
  end if;

  -- Enqueue via helper terpusat (auth header + URL dari config + log).
  perform public.ai_reply_post(
    new.chat_id, new.id, new.sender_id, v_other, false
  );

  return new;
end;
$function$

-- snapshot-fn: ai_reply_post @ 20260914060000_ai_reply_log_fix.sql
CREATE OR REPLACE FUNCTION public.ai_reply_post(p_chat_id text, p_trigger_msg_id bigint, p_sender_id uuid, p_dummy_uid uuid, p_proactive boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_url text;
  v_secret text;
begin
  select value into v_url from public.ai_internal_config where key = 'ai_reply_url';
  select value into v_secret from public.ai_internal_config where key = 'callback_secret';
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'skipped:no_secret', '{}');
    return;
  end if;
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-app-secret', v_secret
      ),
      body := jsonb_build_object(
        'chat_id', p_chat_id,
        'trigger_msg_id', p_trigger_msg_id,
        'sender_id', p_sender_id,
        'dummy_uid', p_dummy_uid,
        'proactive', coalesce(p_proactive, false)
      ),
      timeout_milliseconds := 60000
    );
  exception when others then
    perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'error:post_failed', jsonb_build_object('err', sqlerrm));
    return;
  end;
  perform public.ai_log_reply(p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, p_proactive, 'enqueue', 'enqueued', jsonb_build_object('proactive', coalesce(p_proactive, false)));
end;
$function$

-- snapshot-fn: ai_reply_claim_recovery @ 20260914040000_ai_missed_recovery.sql
CREATE OR REPLACE FUNCTION public.ai_reply_claim_recovery()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r record;
begin
  for r in
    select c.trigger_msg_id, c.dummy_uid, m.chat_id, m.sender_id
    from public.ai_reply_claims c
    join public.private_messages m on m.id = c.trigger_msg_id
    where c.claimed_at < now() - interval '10 minutes'
      and c.claimed_at > now() - interval '1 hour'
      and not exists (
        select 1 from public.private_messages m2
        where m2.chat_id = m.chat_id
          and m2.sender_id = c.dummy_uid
          and m2.id > c.trigger_msg_id
      )
  loop
    begin
      -- Helper terpusat: URL + x-app-secret dari ai_internal_config.
      perform public.ai_reply_post(
        r.chat_id, r.trigger_msg_id, r.sender_id, r.dummy_uid, false
      );
      delete from public.ai_reply_claims
        where trigger_msg_id = r.trigger_msg_id;
    exception when others then
      null;
    end;
  end loop;
  delete from public.ai_reply_claims
    where claimed_at < now() - interval '1 hour';
end;
$function$

-- snapshot-fn: admin_set_dummy_ai @ 20260913190001_dummy_photos_toggle.sql
CREATE OR REPLACE FUNCTION public.admin_set_dummy_ai(p_uid uuid, p_enabled boolean, p_persona jsonb DEFAULT '{}'::jsonb, p_schedule_auto boolean DEFAULT NULL::boolean, p_guard_enabled boolean DEFAULT NULL::boolean, p_max_replies integer DEFAULT NULL::integer, p_min_interval integer DEFAULT NULL::integer, p_no_rate_limit boolean DEFAULT NULL::boolean, p_active_hours jsonb DEFAULT NULL::jsonb, p_model text DEFAULT NULL::text, p_photos_enabled boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$

-- snapshot-fn: admin_ai_settings @ 20260915090000_ai_ai_chat_toggle.sql
CREATE OR REPLACE FUNCTION public.admin_ai_settings(p_global_enabled boolean DEFAULT NULL::boolean, p_max_replies integer DEFAULT NULL::integer, p_min_interval integer DEFAULT NULL::integer, p_guard_enabled boolean DEFAULT NULL::boolean, p_api_base text DEFAULT NULL::text, p_api_key text DEFAULT NULL::text, p_default_model text DEFAULT NULL::text, p_stt_base text DEFAULT NULL::text, p_stt_key text DEFAULT NULL::text, p_ai_ai_enabled boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_row public.app_settings;
  v_prov public.ai_provider_config;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  insert into public.app_settings (id) values ('global')
  on conflict (id) do nothing;

  update public.app_settings
  set ai_global_enabled = coalesce(p_global_enabled, ai_global_enabled),
      ai_max_replies_per_hour = coalesce(p_max_replies, ai_max_replies_per_hour),
      ai_min_interval_sec = coalesce(p_min_interval, ai_min_interval_sec),
      ai_guard_enabled = coalesce(p_guard_enabled, ai_guard_enabled),
      ai_ai_chat_enabled = coalesce(p_ai_ai_enabled, ai_ai_chat_enabled),
      updated_at = now()
  where id = 'global'
  returning * into v_row;

  -- Hanya pastikan baris provider bila ada field provider yang ditulis.
  -- Tanpa ini, baris 'global' yang sengaja dihapus user bangkit lagi
  -- di setiap pembacaan (GET tanpa parameter).
  if p_api_base is not null
     or p_api_key is not null
     or p_default_model is not null
     or p_stt_base is not null
     or p_stt_key is not null then
    insert into public.ai_provider_config (id) values ('global')
    on conflict (id) do nothing;
  end if;

  update public.ai_provider_config
  set api_base = coalesce(p_api_base, api_base),
      api_key = coalesce(p_api_key, api_key),
      default_model = coalesce(p_default_model, default_model),
      stt_api_base = coalesce(p_stt_base, stt_api_base),
      stt_api_key = coalesce(p_stt_key, stt_api_key),
      updated_at = now()
  where id = 'global'
  returning * into v_prov;

  return jsonb_build_object(
    'ai_global_enabled', v_row.ai_global_enabled,
    'ai_max_replies_per_hour', v_row.ai_max_replies_per_hour,
    'ai_min_interval_sec', v_row.ai_min_interval_sec,
    'ai_guard_enabled', v_row.ai_guard_enabled,
    'ai_ai_chat_enabled', v_row.ai_ai_chat_enabled,
    'ai_api_base', v_prov.api_base,
    'ai_api_key', v_prov.api_key,
    'ai_default_model', v_prov.default_model,
    'ai_stt_base', v_prov.stt_api_base,
    'ai_stt_key', v_prov.stt_api_key
  );
end;
$function$

-- snapshot-fn: admin_register_dummy @ 20260905090001_dummy_profile_edit_fix.sql
CREATE OR REPLACE FUNCTION public.admin_register_dummy(p_uid uuid, p_nickname text, p_refresh_token text, p_gender text DEFAULT 'male'::text, p_age integer DEFAULT 25, p_country text DEFAULT 'Indonesia'::text, p_city text DEFAULT 'Jakarta'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  if p_gender not in ('male', 'female') then
    raise exception 'Gender tidak valid';
  end if;
  if p_age < 18 or p_age > 80 then
    raise exception 'Umur tidak valid';
  end if;
  if length(trim(p_nickname)) < 3 or length(p_nickname) > 20 then
    raise exception 'Nickname harus 3-20 karakter';
  end if;
  if exists (select 1 from public.profiles where lower(nickname) = lower(trim(p_nickname))) then
    raise exception 'Nickname sudah dipakai';
  end if;
  insert into public.profiles (id, nickname, gender, age, country, city, status, is_registered, last_seen)
  values (p_uid, p_nickname, p_gender, p_age, p_country, p_city, 'offline', true, now())
  on conflict (id) do update set
    nickname = excluded.nickname,
    gender = excluded.gender,
    age = excluded.age,
    country = excluded.country,
    city = excluded.city,
    last_seen = now();
  insert into public.dummy_accounts (uid, nickname, refresh_token)
  values (p_uid, p_nickname, p_refresh_token)
  on conflict (uid) do update set
    nickname = excluded.nickname,
    refresh_token = excluded.refresh_token;
  return jsonb_build_object('ok', true, 'uid', p_uid);
end;
$function$

-- snapshot-fn: notify_private_message @ 20260913130001_notif_touid.sql
CREATE OR REPLACE FUNCTION public.notify_private_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  receiver_id uuid;
  receiver_token text;
  sender_display text;
  sender_avatar text;
  v_body text;
begin
  begin
    if new.type = 'call' then
      if exists (
        select 1 from public.private_messages
        where chat_id = new.chat_id
          and type = 'call'
          and created_at > now() - interval '30 seconds'
          and id <> new.id
      ) then
        return new;
      end if;
      select p into receiver_id from (
        select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
      ) x where x.p <> new.sender_id limit 1;
      if receiver_id is null then return new; end if;
      select fcm_token into receiver_token from public.profiles where id = receiver_id;
      if receiver_token is null or receiver_token = '' then return new; end if;
      select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
      sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', receiver_token,
          'title', sender_display,
          'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
          'data', jsonb_build_object(
            'type', 'missed_call',
            'toUid', receiver_id,
            'chatId', new.chat_id,
            'otherUid', new.sender_id,
            'otherName', sender_display,
            'callText', coalesce(new.text, 'Missed call'),
            'avatarUrl', coalesce(sender_avatar,''),
            'message', coalesce(nullif(new.text,''), 'Panggilan tak terjawab'),
            'body', coalesce(nullif(new.text,''), 'Panggilan tak terjawab')
          )
        )
      );
      return new;
    end if;

    select p into receiver_id from (
      select unnest(pc.participants) as p from public.private_chats pc where pc.chat_id = new.chat_id
    ) x where x.p <> new.sender_id limit 1;
    if receiver_id is null then return new; end if;
    select fcm_token into receiver_token from public.profiles where id = receiver_id;
    if receiver_token is null or receiver_token = '' then return new; end if;
    select nickname, avatar into sender_display, sender_avatar from public.profiles where id = new.sender_id;
    sender_display := coalesce(nullif(sender_display,''), nullif(new.sender_name,''), 'User');
    -- Preview isi: teks (200 char) atau label tipe non-teks.
    v_body := case when new.type in ('image','view_once') then '[Foto]'
                   when new.type = 'voice' then '[Pesan suara]'
                   when new.type = 'coin' then '[Koin]'
                   when new.type = 'gift' then '[Hadiah]'
                   else left(coalesce(new.text,''), 200) end;
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
      body := jsonb_build_object(
        'token', receiver_token,
        'title', sender_display,
        'body', v_body,
        'data', jsonb_build_object(
          'type', 'message',
          'toUid', receiver_id,
          'chatId', new.chat_id,
          'otherUid', new.sender_id,
          'otherName', sender_display,
          'avatarUrl', coalesce(sender_avatar,''),
          'message', v_body,
          'body', v_body
        )
      )
    );
  exception when others then null;
  end;
  return new;
end; $function$

-- snapshot-fn: notify_call_ended @ 20260913130001_notif_touid.sql
CREATE OR REPLACE FUNCTION public.notify_call_ended()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rec record;
  v_chat_id text;
  v_name text;
  v_body text;
  sent boolean := false;
begin
  -- Hanya transisi pertama dari ringing/answered ke terminal
  if old.status not in ('ringing','answered') then return new; end if;
  if new.status not in ('canceled','missed','declined','ended','busy') then return new; end if;
  -- Idempoten: jika sudah pernah kirim untuk call ini, jangan kirim lagi
  if new.notif_sent_at is not null then return new; end if;

  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' || greatest(new.caller_id::text, new.callee_id::text);
  select nickname into v_name from public.profiles where id = new.caller_id;
  v_name := coalesce(nullif(v_name,''), 'User');
  v_body := case
    when new.status in ('ended','canceled') then 'Call ended'
    when new.status = 'missed' then 'Missed call'
    when new.status = 'declined' then 'Call declined'
    when new.status = 'busy' then 'Busy'
    else 'Call ended'
  end;

  for rec in
    select fcm_token from public.user_devices
    where user_id = new.callee_id and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', rec.fcm_token,
          'title', v_name,
          'body', v_body,
          'data', jsonb_build_object(
            'type', 'call_ended',
            'toUid', new.callee_id,
            'callId', new.id,
            'chatId', v_chat_id,
            'callerUid', new.caller_id,
            'otherName', v_name
          )
        )
      );
    exception when others then null;
    end;
  end loop;

  if not sent then
    declare t text;
    begin
      select fcm_token into t from public.profiles where id = new.callee_id;
      if t is not null and t <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'title', v_name,
            'body', v_body,
            'data', jsonb_build_object(
              'type', 'call_ended',
              'toUid', new.callee_id,
              'callId', new.id,
              'chatId', v_chat_id,
              'callerUid', new.caller_id,
              'otherName', v_name
            )
          )
        );
      end if;
    exception when others then null;
    end;
  end if;

  -- Tandai sudah dikirim supaya update berikutnya tidak kirim lagi
  new.notif_sent_at := now();
  return new;
exception when others then return new;
end; $function$

-- snapshot-fn: call_push @ 20260913130001_notif_touid.sql
CREATE OR REPLACE FUNCTION public.call_push(p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rec record;
  sent boolean := false;
  v_chat_id text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  -- fan-out ke semua device aktif
  for rec in
    select fcm_token from public.user_devices
    where user_id = p_callee and is_active = true and coalesce(fcm_token,'') <> ''
  loop
    sent := true;
    begin
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
        body := jsonb_build_object(
          'token', rec.fcm_token,
          'title', p_name,
          'body', p_call_type,
          'data', jsonb_build_object(
            'type', 'call',
            'callId', p_call,
            'callerUid', p_caller,
            'fromName', p_name,
            'otherName', p_name,
            'callType', p_call_type,
            'chatId', v_chat_id
          )
        )
      );
    exception when others then null;
    end;
  end loop;

  if not sent then
    declare t text;
    begin
      select fcm_token into t from public.profiles where id = p_callee;
      if t is not null and t <> '' then
        perform net.http_post(
          url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
          body := jsonb_build_object(
            'token', t,
            'title', p_name,
            'body', p_call_type,
            'data', jsonb_build_object(
              'type', 'call',
              'callId', p_call,
              'callerUid', p_caller,
              'fromName', p_name,
              'otherName', p_name,
              'callType', p_call_type,
              'chatId', v_chat_id
            )
          )
        );
      end if;
    exception when others then null;
    end;
  end if;
end;
$function$

-- snapshot-fn: handle_new_private_message @ 20260814250000_gift_platform_cut_phase3.sql
CREATE OR REPLACE FUNCTION public.handle_new_private_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  receiver uuid;
  unread jsonb := '{}'::jsonb;
  lastread jsonb := '{}'::jsonb;
begin
  select p2 into receiver from (
    select unnest(participants) as p2 from public.private_chats where chat_id = new.chat_id
  ) x where p2 <> new.sender_id limit 1;
  if receiver is null then return new; end if;

  select coalesce(unread_counts, '{}'::jsonb) into unread from public.private_chats where chat_id = new.chat_id;
  if unread is null then unread := '{}'::jsonb; end if;
  unread := jsonb_set(unread, array[receiver::text], to_jsonb(coalesce((unread->>receiver::text)::int, 0) + 1), true);

  select coalesce(last_read_at, '{}'::jsonb) into lastread from public.private_chats where chat_id = new.chat_id;
  if lastread is null then lastread := '{}'::jsonb; end if;

  update public.private_chats set
    last_message = case
      when new.type = 'image' then '[Foto]'
      when new.type = 'view_once' then '[Foto]'
      when new.type = 'coin' then '[Koin]'
      when new.type = 'gift' then '[Hadiah]'
      else new.text end,
    last_message_at = now(),
    message_count = message_count + 1,
    unread_counts = coalesce(unread, '{}'::jsonb),
    last_read_at = coalesce(lastread, '{}'::jsonb)
  where chat_id = new.chat_id;
  return new;
end; $function$

-- snapshot-fn: create_private_room @ 20260905190000_group_visibility_expiry.sql
CREATE OR REPLACE FUNCTION public.create_private_room(p_name text, p_icon text, p_country text, p_password text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  uid uuid := auth.uid(); points_on boolean;
  has_pw boolean := (p_password is not null and length(p_password) > 0);
  active_count int; new_id text; my_name text;
  paid int; create_paid int; create_pw_paid int; bonus_p int; mult int;
  remaining int; r jsonb;
  is_admin boolean := ((auth.jwt() ->> 'email') = 'zunixe@gmail.com');
  v_token text;
  recent_id text;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  -- Grup hanya untuk TERDAFTAR (bypass: dummy & admin).
  if not is_admin
     and uid not in (select du from public.admin_dummy_uids() du)
     and not coalesce(
       (select is_registered from public.profiles where id = uid), false)
  then
    raise exception 'REGISTERED_ONLY';
  end if;
  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 3 or length(p_name) > 30 then raise exception 'Invalid room name'; end if;
  if p_country is null or p_country = '' then raise exception 'Invalid country'; end if;

  -- Idempotency: jika ada room nama sama owner sama dibuat <10 detik lalu, kembalikan itu
  select id into recent_id from public.rooms
   where owner_id = uid and is_private = true and name = p_name
     and created_at > now() - interval '10 seconds'
   order by created_at desc limit 1;
  if recent_id is not null then
    select join_token into v_token from public.rooms where id = recent_id;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('id', recent_id, 'points', coalesce(remaining, 0), 'join_token', v_token, 'duplicate', true);
  end if;

  if not is_admin then
    select count(*) into active_count from public.rooms
     where owner_id = uid and is_private = true
       and (expires_at is null or expires_at > now());
    if active_count >= 2 then raise exception 'Room limit reached'; end if;
  end if;

  select points_enabled, room_create_paid, room_create_pw_paid, bonus_price_multiplier
    into points_on, create_paid, create_pw_paid, mult from app_settings where id = 'global';
  paid := case when has_pw then create_pw_paid else create_paid end;
  bonus_p := paid * mult;

  if points_on is not false and not is_admin then
    r := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'create');
    remaining := (r->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  select nickname into my_name from public.profiles where id = uid;
  new_id := 'pr_' || replace(gen_random_uuid()::text, '-', '');
  v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 22);

  insert into public.rooms (id, name, description, icon, "order", country, category,
                            is_private, owner_id, owner_name, password_hash, has_password,
                            expires_at, created_at,
                            join_token, max_members, approval_required)
  values (new_id, p_name, '', coalesce(nullif(p_icon, ''), '🔒'), 999, p_country, 'private',
          true, uid, coalesce(my_name, 'Anon'),
          case when has_pw then crypt(p_password, gen_salt('bf')) else null end,
          has_pw,
          -- TANPA password = permanen (NULL); DENGAN password = 7 hari.
          case when has_pw then now() + interval '7 days' else null end,
          now(),
          v_token, 20, true);

  insert into public.room_members (room_id, user_id, role)
  values (new_id, uid, 'owner') on conflict do nothing;

  return jsonb_build_object('id', new_id, 'points', coalesce(remaining, 0), 'join_token', v_token);
end;
$function$

-- snapshot-fn: join_private_room @ 20260827060000_private_room_fixes.sql
CREATE OR REPLACE FUNCTION public.join_private_room(p_room_id text, p_password text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  uid uuid := auth.uid(); r record; r_lock record; points_on boolean;
  am_registered boolean; remaining int; charged int := 0;
  paid int; bonus_p int; mult int; tier text; res jsonb;
  member_count int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select * into r_lock from public.rooms where id = p_room_id for update;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.is_private and r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired'; end if;

  if r.owner_id = uid
     or exists (select 1 from public.room_members m where m.room_id = p_room_id and m.user_id = uid) then
    insert into public.room_members (room_id, user_id, role)
    values (p_room_id, uid, case when r.owner_id = uid then 'owner' else 'member' end)
    on conflict (room_id, user_id) do update set role = excluded.role;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
  end if;

  select count(*) into member_count from public.room_members where room_id = p_room_id;
  if member_count >= r.max_members then raise exception 'Room full'; end if;

  if not r.is_private then
    insert into public.room_members (room_id, user_id, role) values (p_room_id, uid, 'member') on conflict do nothing;
    select points into remaining from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
  end if;

  if r.has_password then
    if p_password is null or r.password_hash is null or crypt(p_password, r.password_hash) <> r.password_hash then
      raise exception 'Wrong password'; end if;
  end if;

  if r.approval_required then
    insert into public.room_join_requests (room_id, user_id)
    values (p_room_id, uid)
    on conflict (room_id, user_id) do update set status = 'pending', requested_at = now(), decided_at = null, decided_by = null;
    return jsonb_build_object('ok', true, 'pending', true, 'charged', 0);
  end if;

  -- Auto-join path: private room sekarang GRATIS (tidak ada ledger), sesuai request "bukan mode koin"
  insert into public.room_members (room_id, user_id, role) values (p_room_id, uid, 'member') on conflict do nothing;
  select points into remaining from public.profiles where id = uid;
  insert into public.room_join_requests (room_id, user_id, status, decided_at) values (p_room_id, uid, 'approved', now()) on conflict (room_id, user_id) do update set status='approved', decided_at=now();
  return jsonb_build_object('ok', true, 'charged', 0, 'points', coalesce(remaining, 0), 'pending', false);
end; $function$

-- snapshot-fn: extend_private_room @ 20260816030000_coin_economy_v2.sql
CREATE OR REPLACE FUNCTION public.extend_private_room(p_room_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  uid uuid := auth.uid(); r record; points_on boolean;
  paid int; bonus_p int; mult int; remaining int; res jsonb;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  select * into r from public.rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.owner_id <> uid then raise exception 'Not owner'; end if;

  select points_enabled, room_extend_paid, bonus_price_multiplier
    into points_on, paid, mult from app_settings where id = 'global';
  bonus_p := paid * mult;

  if points_on is not false then
    res := public.ledger_spend_dual(uid, 'spend_room', paid, bonus_p, 'extend');
    remaining := (res->>'remaining')::int;
  else
    select points into remaining from public.profiles where id = uid;
  end if;

  update public.rooms
    set expires_at = greatest(coalesce(expires_at, now()), now()) + interval '7 days'
    where id = p_room_id returning expires_at into r.expires_at;

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
                            'expires_at', r.expires_at);
end; $function$

-- snapshot-fn: deduct_chat_point @ points_v1.sql
CREATE OR REPLACE FUNCTION public.deduct_chat_point(msg_type text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare points_on boolean; cost int; remaining int; c_text int; c_img int; c_vo int;
begin
  select points_enabled, cost_chat_text, cost_chat_image, cost_view_once
    into points_on, c_text, c_img, c_vo from app_settings where id = 'global';
  if points_on is false then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;

  cost := case msg_type
    when 'image' then c_img
    when 'view_once' then c_vo
    when 'view_once_expired' then 0
    else c_text end;

  if cost = 0 then
    select points into remaining from profiles where id = auth.uid();
    return coalesce(remaining, 0);
  end if;

  remaining := public.ledger_spend(auth.uid(), 'spend_chat', cost, msg_type);
  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));
  return remaining;
end; $function$

-- snapshot-fn: new_chat_bonus @ 20260816030000_coin_economy_v2.sql
CREATE OR REPLACE FUNCTION public.new_chat_bonus(other_uid uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare points_on boolean; tot int; ok boolean; nc int; lim int;
begin
  select points_enabled, bonus_new_chat, new_chats_daily_limit
    into points_on, nc, lim from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  if exists (select 1 from point_events where user_id = auth.uid()
             and event = 'new_chat' and metadata->>'other_uid' = other_uid::text) then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  update profiles set new_chats_today = new_chats_today + 1
    where id = auth.uid() and new_chats_today < lim;
  ok := found;
  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'new_chat', nc,
             null, jsonb_build_object('other_uid', other_uid));
    insert into point_events (user_id, event, amount, metadata)
      values (auth.uid(), 'new_chat', nc, jsonb_build_object('other_uid', other_uid));
    return tot;
  end if;
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: one_time_bonus @ points_v1.sql
CREATE OR REPLACE FUNCTION public.one_time_bonus(action_key text, bonus integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  valid_actions text[]; nominal int; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  valid_actions := array['registered','rated_app','completed_profile',
    'shared_app','invited_friend','first_photo','first_room_chat',
    'online_5min','online_30min','online_60min','online_120min',
    'first_friend'];
  if not (action_key = any(valid_actions)) then
    raise exception 'Invalid action key: %', action_key;
  end if;

  -- Nominal dibaca dari server, bukan dari client (anti-farming).
  select
    case action_key
      when 'registered'        then bonus_registered
      when 'rated_app'         then bonus_rated
      when 'completed_profile' then bonus_profile
      when 'shared_app'        then bonus_shared
      when 'invited_friend'    then bonus_invited
      when 'first_photo'       then bonus_first_photo
      when 'first_room_chat'   then bonus_first_room
      when 'online_5min'       then bonus_online_5min
      when 'online_30min'      then bonus_online_30min
      when 'online_60min'      then bonus_online_60min
      when 'online_120min'     then bonus_online_120min
      when 'first_friend'      then bonus_first_friend
      else 0
    end
  into nominal from app_settings where id = 'global';

  if exists (select 1 from profiles where id = auth.uid()
             and one_time_actions->>action_key = 'true') then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;

  update profiles set one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
    where id = auth.uid();

  tot := public.ledger_credit(auth.uid(), 'bonus', 'one_time', nominal,
           null, jsonb_build_object('action', action_key));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'bonus', nominal, jsonb_build_object('action', action_key));

  return tot;
end; $function$

-- snapshot-fn: send_coins @ 20260816030000_coin_economy_v2.sql
CREATE OR REPLACE FUNCTION public.send_coins(p_chat_id text, p_receiver_id uuid, p_amount integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;

  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- Hanya koin belian (topup+earned) — koin bonus TIDAK bisa ditransfer.
  remaining := public.ledger_spend_paid(uid, 'coin_sent', p_amount, p_chat_id);

  -- Penerima selalu dapat 'earned' (bisa dicairkan setelah KYC).
  perform public.ledger_credit(p_receiver_id, 'earned', 'coin_received', p_amount,
    p_chat_id, jsonb_build_object('from', uid));

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', p_amount);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0));
end; $function$

-- snapshot-fn: send_gift @ 20260816030000_coin_economy_v2.sql
CREATE OR REPLACE FUNCTION public.send_gift(p_chat_id text, p_receiver_id uuid, p_gift_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int; mult int;
  my_name text; my_gender text; am_registered boolean;
  n int; bonus_price int; cut int; net int;
  tier text; remaining int; recv_bucket text; recv_amount int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;

  select points_enabled, coalesce(gift_cut_pct,30), coalesce(bonus_price_multiplier,3)
    into points_on, cut_pct, mult from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;

  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;
  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  bonus_price := n * mult;
  tier := (public.ledger_spend_dual(uid, 'gift_sent', n, bonus_price, p_chat_id))->>'tier';
  remaining := public.wallet_sync_points(uid);

  if tier = 'paid' then
    cut := (n * cut_pct) / 100;
    net := n - cut;
    recv_bucket := 'earned';
    recv_amount := net;
    if cut > 0 then
      insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
        values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
                jsonb_build_object('gift', p_gift_id, 'gross', n, 'net', net, 'pct', cut_pct));
    end if;
  else
    net := n;
    cut := 0;
    recv_bucket := 'bonus';
    recv_amount := bonus_price;
  end if;

  if recv_amount > 0 then
    perform public.ledger_credit(p_receiver_id, recv_bucket, 'gift_recv', recv_amount,
      p_chat_id, jsonb_build_object('gift', p_gift_id, 'from', uid, 'tier', tier));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -case when tier = 'paid' then n else bonus_price end,
            jsonb_build_object('gift', p_gift_id, 'tier', tier)),
           (p_receiver_id, 'gift_recv', recv_amount,
            jsonb_build_object('gift', p_gift_id, 'tier', tier));

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut, 'tier', tier);
end; $function$

-- snapshot-fn: room_read_bonus @ points_v1.sql
CREATE OR REPLACE FUNCTION public.room_read_bonus()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare points_on boolean; ok boolean; tot int; rr int; lim int;
begin
  select points_enabled, bonus_room_read, room_reads_daily_limit
    into points_on, rr, lim from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return coalesce(tot, 0);
  end if;
  update profiles set room_reads_today = room_reads_today + 1
    where id = auth.uid() and room_reads_today < lim;
  ok := found;
  if ok then
    tot := public.ledger_credit(auth.uid(), 'bonus', 'room_read', rr);
    insert into point_events (user_id, event, amount) values (auth.uid(), 'room_read', rr);
    return tot;
  end if;
  select points into tot from profiles where id = auth.uid();
  return coalesce(tot, 0);
end; $function$

-- snapshot-fn: daily_login_bonus @ points_v1.sql
CREATE OR REPLACE FUNCTION public.daily_login_bonus()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  today date; last_date date; cur_streak int; new_streak int; bonus int;
  cur_points int; points_on boolean; tot int;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into cur_points from profiles where id = auth.uid();
    return jsonb_build_object('points', coalesce(cur_points,0), 'streak', 0, 'bonus', 0);
  end if;

  today := (now() at time zone 'Asia/Jakarta')::date;
  select last_login_date, login_streak, points
    into last_date, cur_streak, cur_points
    from profiles where id = auth.uid();

  if last_date is not null and last_date >= today then
    return jsonb_build_object('points', coalesce(cur_points,0),
      'streak', coalesce(cur_streak,0), 'bonus', 0);
  end if;

  if last_date is not null and last_date = today - 1 then
    new_streak := coalesce(cur_streak,0) + 1;
    if new_streak > 7 then new_streak := 1; end if;
  else
    new_streak := 1;
  end if;
  bonus := public.streak_bonus_amount(new_streak);

  update profiles set
    login_streak = new_streak,
    last_login_date = today,
    login_at = now(),
    room_reads_today = 0,
    new_chats_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min']
  where id = auth.uid();

  tot := public.ledger_credit(auth.uid(), 'bonus', 'daily_login', bonus,
           null, jsonb_build_object('streak', new_streak));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'daily_login', bonus, jsonb_build_object('streak', new_streak));

  return jsonb_build_object('points', tot, 'streak', new_streak, 'bonus', bonus);
end; $function$

-- snapshot-fn: claim_weekly_quest @ 20260815010000_points_admin_dev_bypass.sql
CREATE OR REPLACE FUNCTION public.claim_weekly_quest(quest_key text, tz_offset_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare wk_start timestamptz; wk text; progress int; target int; tot int; points_on boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    select points into tot from profiles where id = auth.uid();
    return jsonb_build_object('points', coalesce(tot,0), 'claimed', false);
  end if;

  if quest_key not in ('w_login','w_social','w_active') then
    raise exception 'Invalid quest key: %', quest_key;
  end if;

  wk_start := public.week_start_utc(tz_offset_minutes);
  wk := public.week_label(tz_offset_minutes);

  if exists (select 1 from point_events where user_id = auth.uid()
    and event = 'weekly_quest' and metadata->>'key' = quest_key and metadata->>'week' = wk) then
    select points into tot from profiles where id = auth.uid();
    return jsonb_build_object('points', coalesce(tot,0), 'claimed', false);
  end if;

  if quest_key = 'w_login' then
    select count(distinct (created_at + make_interval(mins => tz_offset_minutes))::date)
      into progress from point_events
      where user_id = auth.uid() and event = 'daily_login' and created_at >= wk_start;
    target := 5;
  elsif quest_key = 'w_social' then
    select count(*) into progress from point_events
      where user_id = auth.uid() and event = 'new_chat' and created_at >= wk_start;
    target := 10;
  else
    select count(*) into progress from point_events
      where user_id = auth.uid() and event = 'deduct' and created_at >= wk_start;
    target := 100;
  end if;

  if progress < target then
    raise exception 'Quest not completed: % (%/%)', quest_key, progress, target;
  end if;

  tot := public.ledger_credit(auth.uid(), 'bonus', 'weekly_quest', 50,
           null, jsonb_build_object('key', quest_key, 'week', wk));

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'weekly_quest', 50, jsonb_build_object('key', quest_key, 'week', wk));

  return jsonb_build_object('points', tot, 'claimed', true);
end; $function$

-- snapshot-fn: points_leaderboard @ 20260913000000_leaderboard_history_pagination.sql
CREATE OR REPLACE FUNCTION public.points_leaderboard(scope text DEFAULT 'weekly'::text, row_limit integer DEFAULT 50, row_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  me jsonb;
  lim int;
  off int;
begin
  lim := least(greatest(coalesce(row_limit, 50), 1), 100);
  off := greatest(coalesce(row_offset, 0), 0);

  if scope = 'alltime' then
    with ranked as (
      select
        p.id, p.nickname, p.avatar, p.country, p.points as score, p.is_registered,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank > off and rank <= off + lim;

    with ranked as (
      select p.id, p.points as score,
        row_number() over (order by p.points desc, p.created_at asc) as rank
      from profiles p
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = auth.uid();
  else
    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select
        p.id, p.nickname, p.avatar, p.country, en.score, p.is_registered,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'rank', rank, 'uid', id, 'nickname', nickname,
        'avatar', avatar, 'country', country, 'score', score,
        'is_registered', is_registered
      ) order by rank), '[]'::jsonb)
    into result from ranked where rank > off and rank <= off + lim;

    with earned as (
      select e.user_id, sum(e.amount)::int as score
      from point_events e
      where e.created_at >= now() - interval '7 days' and e.amount > 0
      group by e.user_id
    ), ranked as (
      select p.id, en.score,
        row_number() over (order by en.score desc, p.created_at asc) as rank
      from earned en
      join profiles p on p.id = en.user_id
      where p.status <> 'invisible' and (p.is_registered = true or p.status <> 'offline')
    )
    select jsonb_build_object('rank', rank, 'score', score)
    into me from ranked where id = auth.uid();
  end if;

  return jsonb_build_object(
    'scope', case when scope = 'alltime' then 'alltime' else 'weekly' end,
    'entries', coalesce(result, '[]'::jsonb),
    'me', coalesce(me, 'null'::jsonb)
  );
end;
$function$

-- snapshot-fn: list_posts @ 20260909000001_timeline_listposts_perf.sql
CREATE OR REPLACE FUNCTION public.list_posts(p_scope text DEFAULT 'all'::text, p_limit integer DEFAULT 30, p_cursor timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_boosted boolean DEFAULT false, p_country text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  rows jsonb;
  v_followers uuid[] := '{}';
  v_subs uuid[] := '{}';
  v_blocked uuid[] := '{}';
begin
  if me is null then raise exception 'Not authenticated'; end if;
  -- Timeline registered-only (ABSOLUT, tak tergantung toggle):
  -- anon tidak pernah bisa lihat timeline/post (bypass: dummy & admin).
  if exists (
    select 1 from public.profiles p
    where p.id = me and p.is_registered = false
      and p.id not in (select du from public.admin_dummy_uids() du)
  ) then
    raise exception 'ANON_DISABLED';
  end if;
  if p_scope not in ('all','following','mine') then p_scope := 'all'; end if;
  p_limit := least(coalesce(p_limit, 30), 50);

  -- Ambil set relasi SEKALI (index-supported, 1 query masing-masing)
  -- daripada EXISTS per baris posts.
  select coalesce(array_agg(f.followee_id), '{}') into v_followers
  from public.follows f where f.follower_id = me;

  select coalesce(array_agg(s.creator_id), '{}') into v_subs
  from public.subscriptions s
  where s.subscriber_id = me and s.expires_at > now();

  select coalesce(array_agg(
    case when b.blocker_id = me then b.blocked_id else b.blocker_id end
  ), '{}') into v_blocked
  from public.blocks b
  where b.blocker_id = me or b.blocked_id = me;

  with visible as (
    select p.*
    from public.posts p
    where
      (p_cursor is null
        or p.is_boosted < p_cursor_boosted
        or (p.is_boosted = p_cursor_boosted and p.created_at < p_cursor))
      and (
        p.visibility = 'public'
        or p.author_id = me
        or (p.visibility = 'followers' and p.author_id = any(v_followers))
        or (p.visibility = 'followers' and p.author_id = any(v_subs))
        or (p.visibility = 'subscribers' and p.author_id = any(v_subs))
      )
      and p.author_id <> all(v_blocked)
      and (
        p_scope = 'all'
        or (p_scope = 'mine' and p.author_id = me)
        or (p_scope = 'following' and p.author_id = any(v_followers))
      )
    order by p.is_boosted desc, p.created_at desc
    limit p_limit
  )
  select jsonb_agg(
    jsonb_build_object(
      'id', v.id,
      'authorId', v.author_id,
      'authorName', v.author_name,
      'authorGender', v.author_gender,
      'text', v.text,
      'imagePath', v.image_path,
      'visibility', v.visibility,
      'likeCount', v.like_count,
      'commentCount', v.comment_count,
      'shareCount', v.share_count,
      'isBoosted', v.is_boosted,
      'createdAt', v.created_at,
      'authorAvatar', pr.avatar,
      'isLiked', s.is_liked,
      'isFollowing', s.is_following,
      'isFriend', s.is_friend,
      'country', v.country
    )
    order by v.is_boosted desc, v.created_at desc
  )
  into rows
  from visible v
  left join public.profiles pr on pr.id = v.author_id
  left join lateral (
    select
      exists (select 1 from public.post_likes pl where pl.post_id = v.id and pl.user_id = me) as is_liked,
      (v.author_id = any(v_followers)) as is_following,
      exists (
        select 1 from public.follows a
        join public.follows b on a.followee_id = b.follower_id and a.follower_id = b.followee_id
        where a.follower_id = me and a.followee_id = v.author_id) as is_friend
  ) s on true;

  return jsonb_build_object('posts', coalesce(rows, '[]'::jsonb));
end;
$function$

-- snapshot-fn: story_slides @ 20260910000003_story_slides_visibility.sql
CREATE OR REPLACE FUNCTION public.story_slides(p_author uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'image_path', s.image_path,
    'text_overlay', s.text_overlay,
    'text_x', s.text_x,
    'text_y', s.text_y,
    'text_color', s.text_color,
    'text_size', s.text_size,
    'text_bg', s.text_bg,
    'visibility', s.visibility,
    'created_at', s.created_at
  ) order by s.created_at asc), '[]'::jsonb)
  into result
  from public.stories s
  where s.author_id = p_author
    and s.expires_at > now()
    and (
      s.author_id = auth.uid()
      or (
        (s.visibility = 'everyone')
        or (s.visibility = 'registered' and public._viewer_is_registered())
        or (s.visibility = 'friends' and public._are_friends(auth.uid(), s.author_id))
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = s.author_id)
           or (b.blocker_id = s.author_id and b.blocked_id = auth.uid())
      )
    );
  return result;
end;
$function$

-- snapshot-fn: create_story @ 20260907100000_story_visibility_followers.sql
CREATE OR REPLACE FUNCTION public.create_story(p_image_path text, p_text_overlay text DEFAULT ''::text, p_text_x real DEFAULT 0.5, p_text_y real DEFAULT 0.85, p_text_color integer DEFAULT 0, p_text_size integer DEFAULT 1, p_text_bg boolean DEFAULT false, p_text_scale real DEFAULT 1.0, p_text_rotation real DEFAULT 0, p_visibility text DEFAULT 'followers'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_vis text;
begin
  if not public._viewer_is_registered() then
    v_vis := 'everyone';
  elsif p_visibility not in ('everyone','followers','friends') then
    if p_visibility = 'registered' then
      v_vis := 'followers';
    else
      raise exception 'Visibility tidak valid';
    end if;
  else
    v_vis := p_visibility;
  end if;
  if length(coalesce(p_text_overlay, '')) > 300 then
    raise exception 'Teks terlalu panjang (max 300)';
  end if;
  insert into public.stories (
    author_id, author_name, image_path, text_overlay, text_x, text_y,
    text_color, text_size, text_bg, text_scale, text_rotation, visibility
  )
  select auth.uid(),
         coalesce((select nickname from public.profiles where id = auth.uid()), 'Anon'),
         p_image_path, coalesce(p_text_overlay, ''),
         greatest(least(coalesce(p_text_x, 0.5), 1), 0),
         greatest(least(coalesce(p_text_y, 0.85), 1), 0),
         greatest(least(coalesce(p_text_color, 0), 7), 0),
         greatest(least(coalesce(p_text_size, 1), 2), 0),
         coalesce(p_text_bg, false),
         greatest(coalesce(p_text_scale, 1.0), 0.1),
         coalesce(p_text_rotation, 0),
         v_vis
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$

-- snapshot-fn: follow_count_sync @ 20260907150000_follow_count_join_profiles.sql
CREATE OR REPLACE FUNCTION public.follow_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  update public.profiles p
  set
    followers_count = (
      select count(*) from public.follows f
      join public.profiles fp on fp.id = f.follower_id
      where f.followee_id = p.id and f.follower_id <> p.id
    ),
    following_count = (
      select count(*) from public.follows f
      join public.profiles fe on fe.id = f.followee_id
      where f.follower_id = p.id and f.followee_id <> p.id
    ),
    friends_count = (
      select count(*) from public.follows a
      join public.follows b
        on a.followee_id = b.follower_id and a.follower_id = b.followee_id
      join public.profiles pa on pa.id = a.follower_id
      join public.profiles pb on pb.id = a.followee_id
      where a.follower_id = p.id and a.followee_id <> p.id
    )
  where p.id in (
    coalesce(new.follower_id, old.follower_id),
    coalesce(new.followee_id, old.followee_id)
  );
  return null; -- AFTER trigger, return value diabaikan
end; $function$

-- snapshot-fn: nearby_users @ 20260903090000_admin_exclude_devices.sql
CREATE OR REPLACE FUNCTION public.nearby_users(p_radius_km double precision DEFAULT 10)
 RETURNS TABLE(uid uuid, nickname text, gender text, age integer, country text, city text, status text, avatar text, is_registered boolean, last_seen timestamp with time zone, distance_km double precision)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  my_lat double precision;
  my_lon double precision;
  radius_m double precision;
  v_excl uuid[];
begin
  if me is null then raise exception 'Not authenticated'; end if;
  radius_m := least(greatest(coalesce(p_radius_km, 10), 1), 500) * 1000.0;

  select p.lat, p.lon into my_lat, my_lon
  from public.profiles p where p.id = me;

  if my_lat is null or my_lon is null then
    raise exception 'No location';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;

  return query
  select
    p.id,
    p.nickname,
    p.gender,
    p.age,
    p.country,
    p.city,
    p.status,
    p.avatar,
    p.is_registered,
    p.last_seen,
    (earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) / 1000.0) as distance_km
  from public.profiles p
  where p.id <> me
    and p.lat is not null
    and p.lon is not null
    and coalesce(p.share_location, false) = true
    and p.status in ('online', 'idle')
    and p.last_seen >= now() - interval '30 minutes'
    and not (p.id = any(v_excl))
    and earth_box(ll_to_earth(my_lat, my_lon), radius_m) @> ll_to_earth(p.lat, p.lon)
    and earth_distance(ll_to_earth(my_lat, my_lon), ll_to_earth(p.lat, p.lon)) <= radius_m
  order by distance_km asc
  limit 100;
end;
$function$

-- snapshot-fn: admin_list_dummies @ 20260914110000_dummy_kind.sql
CREATE OR REPLACE FUNCTION public.admin_list_dummies()
 RETURNS jsonb[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
    'kind', coalesce(d.kind, 'regular'),
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
$function$

-- snapshot-fn: admin_stats_detail @ 20260914010000_admin_anon_sort_last_seen.sql
CREATE OR REPLACE FUNCTION public.admin_stats_detail()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  result jsonb;
  v_excl uuid[];
  v_dummy uuid[];
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(array_agg(ae), '{}'::uuid[]) into v_excl
    from public.admin_excluded_uids() ae;
  select coalesce(array_agg(du), '{}'::uuid[]) into v_dummy
    from public.admin_dummy_uids() du;

  select jsonb_build_object(
    'users_all', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles where not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'
        and not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_registered', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles where is_registered = true
        and not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'users_anonymous', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nickname', nickname, 'gender', gender, 'age', age,
        'country', country, 'city', city, 'ip_address', ip_address,
        'status', status,
        'is_registered', is_registered, 'last_seen', last_seen,
        'lat', lat, 'lon', lon, 'loc_source', loc_source
      ) order by last_seen desc nulls last)
      from profiles where is_registered = false
        and not (id = any(v_excl))
        and not (id = any(v_dummy))), '[]'::jsonb),
    'rooms_active', coalesce((
      select jsonb_agg(jsonb_build_object(
        'room_id', t.room_id,
        'room_name', coalesce(r.name, t.room_id),
        'is_private', coalesce(r.is_private, false),
        'user_count', t.c
      ) order by t.c desc)
      from (select room_id, count(*) as c from room_presence group by room_id) t
      left join rooms r on r.id = t.room_id), '[]'::jsonb),
    'messages_today', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'sender_name', sender_name,
          'text', case when type = 'image' then '[foto]' else text end,
          'type', type,
          'created_at', created_at
        ) as x
        from private_messages
        where created_at >= current_date at time zone 'Asia/Jakarta'
        order by created_at desc
        limit 200
      ) sub), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$

