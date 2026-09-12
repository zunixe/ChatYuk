-- ============================================================
-- Auto-heal cerita harian: cron menandai cerita TIPIS untuk
-- diregenerasi (dihapus) supaya AI membuat ulang saat chat berikutnya.
--
-- Cerita tipis = work kosong DAN aktivitas < 2 (tidak berguna sebagai
-- topik obrolan). Baris lama (bukan hari ini) dibiarkan sebagai sejarah.
-- ============================================================

create or replace function public.ai_story_cleanup()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- Hanya cerita HARI INI (WIB) — hapus bila tipis → regenerate otomatis
  -- pada pesan berikutnya. Cerita hari lampau tetap tersimpan (sejarah).
  delete from public.ai_daily_story
  where story_date = (now() + interval '7 hours')::date
    and coalesce(story->>'work', '') = ''
    and jsonb_array_length(coalesce(story->'activities', '[]'::jsonb)) < 2;
end;
$fn$;

revoke execute on function public.ai_story_cleanup() from public, anon;
grant execute on function public.ai_story_cleanup() to service_role;

-- Gabung ke cron yang sudah ada (tiap 5 menit) — idempotent.
select cron.unschedule('chatyuk-ai-presence')
where exists (select 1 from cron.job where jobname = 'chatyuk-ai-presence');

select cron.schedule(
  'chatyuk-ai-presence',
  '*/5 * * * *',
  $$select public.ai_presence_tick(); select public.ai_story_cleanup();$$
);
