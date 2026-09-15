-- ============================================================
-- RESTORE ai_reply_enqueue + GATE TOGGLE AI↔AI
--
-- Latar: migrasi 20260915090000 (toggle AI↔AI) menulis ulang
-- ai_reply_enqueue dari ingatan, bukan dari definisi live → DUA regresi:
--   1) cabang ai_always_online pada jalur rate_max HILANG
--      (Admin Chatyuk 24 jam bisa diturunkan ke idle saat kena kuota),
--   2) cap AI↔AI (skipped:ai_ai_cap) HILANG.
-- Deteksi: git diff snapshots/functions.sql → ai_always_online -2 +0,
-- ai_no_rate_limit -1 +0 (aturan [5] check_migrations.sh).
--
-- Perbaikan: definisi = SALINAN PERSIS definisi live sebelumnya
-- (snapshot HEAD @ 20260914060000_ai_reply_log_fix.sql) + SATU gate baru
-- (toggle app_settings.ai_ai_chat_enabled). Tidak ada perubahan lain.
--
-- menyentuh: ai_reply_enqueue
-- ============================================================

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
