-- GC stiker yatim (bucket chat-photos / prefix stickers/) via pg_cron harian.
--
-- Edge Function `sticker-gc` (ter-deploy) memindai objek stickers/<uid>/...
-- lalu menghapus yang tak dirujuk pesan private/room mana pun DAN sudah lebih
-- tua dari grace 24 jam (anti hapus stiker yang baru di-upload tapi pesannya
-- belum tersimpan / sedang dikirim).
--
-- Auth: header x-app-secret = app_settings.app_shared_secret (sama pola
-- trigger notif lain; BUKAN anon). Idempotent: cron.schedule mengganti bila
-- nama sama.

select cron.schedule(
  'sticker_gc_daily',
  '40 3 * * *', -- 03:40 UTC tiap hari (sepi)
  $job$
  select net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/sticker-gc',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-app-secret', (select app_shared_secret from public.app_settings where id = 'global')
    ),
    body := jsonb_build_object('graceHours', 24)
  );
  $job$
);
