-- ============================================================
-- Recovery pesan AI yang TAK PERNAH di-claim (kasus Dhanu & Sarah)
--
-- Temuan live 2026-09-14: pesan manusia ke dummy tersimpan di DB tapi
-- tanpa baris claim → ai-reply tidak pernah jalan → pesan tak dibaca
-- (read receipt dibuat function setelah claim) & tak dibalas. Dua lubang:
--
-- 1) ai_reply_claim_recovery (20260913090000) hanya menangani claim BASI,
--    bukan pesan tanpa claim. Bonus bug: ia POST mentah via net.http_post
--    TANPA header auth → selalu 401 sejak gate callback_auth (13130000).
--    Diperbaiki: pakai helper ai_reply_post (URL + secret dari DB).
--
-- 2) Tidak ada backfill untuk pesan manusia (sender BUKAN dummy) umur
--    4–20 menit tanpa claim & tanpa balasan dummy sesudahnya. Baru:
--    ai_reply_missed_recovery (cron tiap 3 menit, maks 20/chat-run,
--    hanya pesan TERBARU per chat — pesan lama otomatis di-skip oleh
--    pause_newer di function). Sender dummy dikecualikan (jalur debounce
--    + proaktif yang menangani; invoke cron ke sana berisiko dobel-balas).
-- ============================================================

-- 1) claim_recovery: ganti POST mentah tanpa-auth → helper ber-auth.
create or replace function public.ai_reply_claim_recovery()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
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
$fn$;

revoke execute on function public.ai_reply_claim_recovery() from public, anon;
grant execute on function public.ai_reply_claim_recovery() to service_role;

select cron.unschedule('chatyuk-ai-claim-recovery')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-claim-recovery');

select cron.schedule(
  'chatyuk-ai-claim-recovery',
  '*/5 * * * *',
  $$select public.ai_reply_claim_recovery();$$
);

-- 2) missed_recovery: pesan manusia tanpa claim sama sekali.
create or replace function public.ai_reply_missed_recovery()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  r record;
begin
  for r in
    with ranked as (
      select m.id as msg_id,
             m.chat_id,
             m.sender_id,
             (select x
                from unnest(pc.participants) as x
               where x <> m.sender_id
               limit 1) as dummy_uid,
             row_number() over (
               partition by m.chat_id order by m.id desc
             ) as rn
        from public.private_messages m
        join public.private_chats pc on pc.chat_id = m.chat_id
       where m.created_at > now() - interval '20 minutes'
         and m.created_at < now() - interval '4 minutes'
         and coalesce(m.type, 'text') = 'text'
         and not exists (
           select 1 from public.dummy_accounts d
            where d.uid = m.sender_id
         )
         and not exists (
           select 1 from public.ai_reply_claims c
            where c.trigger_msg_id = m.id
         )
    )
    select msg_id, chat_id, sender_id, dummy_uid
      from ranked
     where rn = 1
       and dummy_uid is not null
       and exists (
         select 1 from public.dummy_accounts d
          where d.uid = dummy_uid and d.ai_enabled = true
       )
       and not exists (
         select 1 from public.private_messages m2
          where m2.chat_id = ranked.chat_id
            and m2.id > ranked.msg_id
       )
     limit 20
  loop
    begin
      perform public.ai_reply_post(
        r.chat_id, r.msg_id, r.sender_id, r.dummy_uid, false
      );
    exception when others then
      null;
    end;
  end loop;
end;
$fn$;

revoke execute on function public.ai_reply_missed_recovery() from public, anon;
grant execute on function public.ai_reply_missed_recovery() to service_role;

select cron.unschedule('chatyuk-ai-missed-recovery')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-missed-recovery');

select cron.schedule(
  'chatyuk-ai-missed-recovery',
  '*/3 * * * *',
  $$select public.ai_reply_missed_recovery();$$
);
