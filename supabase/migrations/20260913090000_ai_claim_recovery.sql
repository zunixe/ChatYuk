-- ============================================================
-- Recovery balasan AI yang hilang (claim basi)
--
-- Temuan review P0: invokasi ai-reply claim di awal, lalu crash/timeout
-- sebelum insert balasan → trigger itu tidak pernah dibalas (retry
-- terblokir already_claimed sampai claim basi 1 jam).
--
-- ai_reply_claim_recovery (cron tiap 5 menit):
--   - claim umur 10 mnt–1 jam TANPA balasan dummy setelah trigger →
--     invoke ulang edge function (pola net.http_post sama seperti
--     trigger ai_reply_enqueue), lalu hapus claim. Urutan post-dulu-
--     baru-hapus: gagal post = dicoba lagi ronde berikut; gagal hapus =
--     invokasi ekstra terblokir claim (aman, tidak dobel-balas).
--   - claim >1 jam → buang apa pun statusnya (pengaman).
-- ============================================================

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
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-reply',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'chat_id', r.chat_id,
          'trigger_msg_id', r.trigger_msg_id,
          'sender_id', r.sender_id,
          'dummy_uid', r.dummy_uid
        )
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
