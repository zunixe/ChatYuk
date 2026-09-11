-- AI↔AI chat (uji coba Dhanu × Santi):
-- - Blokir "sender dummy" DIHAPUS — dummy AI boleh saling memicu balasan.
-- - Proteksi loop: untuk chat dummy↔dummy, cap KERAS gabungan 40 pesan/jam
--   (flag ai_no_rate_limit TIDAK berlaku di sini) — tanpa ini Santi yang
--   no-rate-limit akan ping-pong tanpa henti.
-- - Chat manusia: perilaku lama tetap (rate limit per dummy, hormati flag).
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
  v_dummy_out_1h int;
  v_ai_ai_1h int;
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

  -- Recipient must be an AI-enabled dummy (ambil flag no-rate-limit sekalian)
  select d.ai_no_rate_limit into v_no_rate
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if v_no_rate is null then
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec
  into v_global, v_max, v_min
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    return new;
  end if;
  v_max := coalesce(v_max, 20);
  v_min := coalesce(v_min, 2);

  if v_sender_is_dummy then
    -- ── AI↔AI: TANPA rate limit (permintaan owner untuk testing).
    -- Satu-satunya stop: matikan Mode AI di salah satu dummy / global.
    null;
  else
    -- ── Sender manusia: rate limit lama (per dummy, hormati no_rate_limit)
    if not coalesce(v_no_rate, false) then
      select count(*) into v_dummy_out_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other
        and m.created_at > now() - interval '1 hour';
      if v_dummy_out_1h >= v_max then
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

  -- EXCEPTION-SAFE: kegagalan enqueue (pg_net down, dsb) TIDAK BOLEH
  -- menggagalkan insert pesan user — fitur AI tidak boleh mengganggu
  -- jalur chat utama.
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
