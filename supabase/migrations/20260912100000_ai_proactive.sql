-- AI PROAKTIF: sapa/cerita duluan kalau lawan diam >45 menit.
-- Cron tiap 10 menit → ai_proactive_tick(): cari chat AI yang pesan
-- terakhirnya dari MANUSIA dan sudah hening >45 mnt, cooldown 1x/3 jam
-- per chat → enqueue ai-reply {proactive: true} via pg_net.
-- Skip: global off, dummy hold, dummy↔dummy sudah aktif dua-duanya
-- (satu sapaan per chat per run — iterasi kedua melihat proactive_at baru).

alter table public.ai_chat_state
  add column if not exists proactive_at timestamptz;

create or replace function public.ai_proactive_tick()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r record;
  v_n int := 0;
begin
  if exists (
    select 1 from public.app_settings
    where id = 'global' and ai_global_enabled = false
  ) then
    return jsonb_build_object('ok', true, 'nudged', 0, 'skipped', 'global_off');
  end if;

  for r in
    select pc.chat_id,
           (select m.sender_id
              from public.private_messages m
             where m.chat_id = pc.chat_id
             order by m.created_at desc limit 1) as last_sender,
           (select max(m.created_at)
              from public.private_messages m
             where m.chat_id = pc.chat_id) as last_at,
           d.uid as dummy_uid
      from public.private_chats pc
      join public.dummy_accounts d
        on d.uid = any (pc.participants) and d.ai_enabled = true
      where coalesce(d.ai_hold_active, false) = false
  loop
    begin
      -- Hanya jika pesan terakhir dari MANUSIA (bukan dummy mana pun)
      if r.last_sender is null then continue; end if;
      if exists (
        select 1 from public.dummy_accounts d2 where d2.uid = r.last_sender
      ) then continue; end if;
      -- Hening >45 menit
      if r.last_at is null or r.last_at > now() - interval '45 minutes' then
        continue;
      end if;
      -- Cooldown 3 jam per chat
      if exists (
        select 1 from public.ai_chat_state s
        where s.chat_id = r.chat_id
          and s.proactive_at > now() - interval '3 hours'
      ) then continue; end if;

      insert into public.ai_chat_state (chat_id, proactive_at, updated_at)
      values (r.chat_id, now(), now())
      on conflict (chat_id) do update
        set proactive_at = now(), updated_at = now();

      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-reply',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'chat_id', r.chat_id,
          'trigger_msg_id', null,
          'sender_id', r.last_sender,
          'dummy_uid', r.dummy_uid,
          'proactive', true
        )
      );
      v_n := v_n + 1;
    exception when others then
      null;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'nudged', v_n);
end;
$$;
revoke execute on function public.ai_proactive_tick() from public, anon;
grant execute on function public.ai_proactive_tick() to authenticated, service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'ai-proactive-10m') then
    perform cron.unschedule('ai-proactive-10m');
  end if;
end $$;
select cron.schedule('ai-proactive-10m', '*/10 * * * *', $$select public.ai_proactive_tick()$$);
