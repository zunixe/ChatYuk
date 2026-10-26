-- STIKER & FILE ikut gate media room publik (keputusan user 2026-10-26).
--
-- Sebelumnya `is_room_media_type` hanya image/video → stiker (GIF/WebP/MP4)
-- dan dokumen (yang bisa berisi video/gambar) bisa dikirim tanpa trust gate,
-- tanpa rate limit, dan tanpa pemeriksaan NSFW.
--
-- SAFE: hanya `create or replace` fungsi milik fitur ini (bukan FROZEN);
--       perilaku room privat & private chat TIDAK berubah (gate hanya
--       berjalan untuk room publik).
create or replace function public.is_room_media_type(p_type text)
returns boolean
language sql
immutable
as $function$
  select coalesce(p_type in (
    'image', 'video', 'video_once', 'video_once_expired',
    'sticker', 'file'
  ), false);
$function$;
