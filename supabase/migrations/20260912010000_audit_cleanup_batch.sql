-- ============================================================
-- Audit cleanup batch:
--   K2: TTL ai_memory 30 hari (fakta usang per pasangan dibuang otomatis).
--   K1: cron harian 05:00 WIB → pre-generate cerita harian semua dummy
--       AI-enabled via edge function ai-daily-life (auth x-app-secret).
-- ============================================================

-- K2: fakta memori > 30 hari dihapus (pasangan yang jarang chat tidak
-- menumpuk fakta basi selamanya).
create or replace function public.ai_memory_cleanup()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  delete from public.ai_memory
  where created_at < now() - interval '30 days';
end;
$fn$;

revoke execute on function public.ai_memory_cleanup() from public, anon;
grant execute on function public.ai_memory_cleanup() to service_role;

-- Cron presence: tambah memory cleanup (idempotent re-schedule).
select cron.unschedule('chatyuk-ai-presence')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-presence');

select cron.schedule(
  'chatyuk-ai-presence',
  '*/5 * * * *',
  $$select public.ai_presence_tick(); select public.ai_story_cleanup(); select public.ai_memory_cleanup();$$
);

-- K1: cron pre-generate cerita harian 05:00 WIB (= 22:00 UTC).
select cron.unschedule('chatyuk-ai-daily-life')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-daily-life');

select cron.schedule(
  'chatyuk-ai-daily-life',
  '0 22 * * *',
  $$select net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/ai-daily-life',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-app-secret', (select app_shared_secret from app_settings where id = 'global')),
    body := jsonb_build_object('source', 'cron')
  );$$
);
