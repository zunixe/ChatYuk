-- ============================================================
-- PERBAIKAN TOGGLE AI↔AI: jalur PROACTIVE masih membocorkan chat dummy↔dummy
--
-- Laporan: setelah tombol AI↔AI dimatikan, Sarah (dummy) masih saling balas
-- dengan dummy lain seolah AI↔AI masih hidup.
--
-- Akar masalah (dua lapis, keduanya di jalur proactive yang mem-bypass
-- trigger ai_reply_enqueue):
--   1) edge ai-reply: gate toggle dibungkus `&& !proactive`
--      → invoke {proactive:true} melewati gate toggle sama sekali.
--   2) sql ai_proactive_tick: hanya menyaring "pengirim terakhir = dummy",
--      TIDAK menyaring chat yang seluruh pesertanya dummy. Di chat
--      dummy×dummy yang admin pegang sesaat (pesan terakhir = admin),
--      tick tetap menyapa → menghidupkan AI↔AI yang sudah dimatikan.
--
-- Perbaikan:
--   a) ai_proactive_tick: kalau toggle OFF → return langsung (skip semua),
--      DAN query loop mengecualikan chat dummy×dummy saat toggle OFF
--      (defense in depth bila toggle dibaca gagal).
--   b) edge ai-reply: gate toggle tidak lagi dikecualikan oleh `proactive`
--      (lihat functions/ai-reply/index.ts, ikut di-deploy bareng file ini).
--
-- menyentuh: ai_proactive_tick
-- ============================================================

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

  -- Tombol AI↔AI OFF: jangan pernah menyapa di chat yang SEMUA pesertanya
  -- dummy. Menyapa di chat dummy×dummy = menghidupkan kembali AI↔AI yang
  -- sudah dimatikan owner (lewat jalur proactive yang bypass trigger).
  if exists (
    select 1 from public.app_settings
    where id = 'global' and coalesce(ai_ai_chat_enabled, true) = false
  ) then
    return jsonb_build_object('ok', true, 'nudged', 0, 'skipped', 'ai_ai_off');
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
        -- Chat dummy×dummy hanya diproses bila tombol AI↔AI ON.
        and (
          coalesce(
            (select s.ai_ai_chat_enabled from public.app_settings s
              where s.id = 'global'), true
          )
          or not exists (
            select 1 from unnest(pc.participants) as p
            where not exists (
              select 1 from public.dummy_accounts dd where dd.uid = p
            )
          )
        )
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
