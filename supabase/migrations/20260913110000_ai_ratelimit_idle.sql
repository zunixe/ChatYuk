-- Rate limit → idle: kuota Maks/jam habis → dummy tampil idle.
-- Sebelumnya trigger diam-diam drop enqueue (dummy tetap online tapi bungkam
-- = terlihat rusak). Kini hanya downgrade online→idle; offline tidak
-- dibangunkan, ai_always_online tidak disentuh. Jeda singkat (min_interval)
-- tetap pacing diam-diam tanpa ubah status.
-- Sekalian perbaiki fallback global: max/min per-dummy NULL kini dibaca dari
-- app_settings (sebelumnya hardcode 20/2 sehingga setting global diabaikan).
create or replace function public.ai_reply_enqueue()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_other uuid;
  v_no_rate boolean;
  v_sender_is_dummy boolean;
  v_global boolean;
  v_max int;
  v_min int;
  v_gmax int;
  v_gmin int;
  v_dummy_out_1h int;
  v_last_dummy_out timestamptz;
begin
  -- Only plain text messages
  if coalesce(new.type, 'text') != 'text' then
    return new;
  end if;

  select x into v_other
  from unnest(
    (select pc.participants from public.private_chats pc where pc.chat_id = new.chat_id)
  ) as x
  where x <> new.sender_id
  limit 1;
  if v_other is null then
    return new;
  end if;

  -- Recipient must be an AI-enabled dummy (ambil rate config sekalian).
  -- PENTING: pakai IF NOT FOUND (bukan cek null!) — kolom flag boleh null.
  select d.ai_no_rate_limit, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if not found then
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec
    into v_global, v_gmax, v_gmin
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    return new;
  end if;
  v_max := coalesce(v_max, v_gmax, 20);
  v_min := coalesce(v_min, v_gmin, 2);

  if v_sender_is_dummy then
    -- ── AI↔AI: TANPA rate limit (permintaan owner untuk testing).
    -- Satu-satunya stop: matikan Mode AI di salah satu dummy / global.
    null;
  else
    -- ── Sender manusia: rate limit (per-dummy override → global)
    if not coalesce(v_no_rate, false) then
      select count(*) into v_dummy_out_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other
        and m.created_at > now() - interval '1 hour';
      if v_dummy_out_1h >= v_max then
        -- Kuota habis → tampil idle (downgrade online→idle saja).
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
        return new;
      end if;

      select max(m.created_at) into v_last_dummy_out
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other;
      if v_last_dummy_out is not null
         and v_last_dummy_out > now() - make_interval(secs => v_min) then
        return new;
      end if;
    end if;
  end if;

  -- EXCEPTION-SAFE: kegagalan enqueue TIDAK BOLEH menggagalkan insert
  -- pesan user — fitur AI tidak boleh mengganggu jalur chat utama.
  begin
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-reply',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'chat_id', new.chat_id,
        'trigger_msg_id', new.id,
        'sender_id', new.sender_id,
        'dummy_uid', v_other
      )
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;
