-- ============================================================
-- Guard storage: izinkan VIDEO story (mp4/mov) di bucket chat-photos.
--
-- Masalah: `chat_photos_guard` hanya meng-whitelist gambar & audio →
-- upload video story ditolak `Tipe file tidak diizinkan: video/mp4`.
-- Akibatnya publish story video selalu gagal (poster JPEG lolos, video
-- tidak).
--
-- Perubahan: tambah tipe video + batas ukuran khusus video 20 MB
-- (video story dikompres client ke ±3 MB; 20 MB jadi jaring pengaman).
-- Batas non-video tetap 8 MB. Fail-closed untuk tipe lain.
-- ============================================================

create or replace function public.chat_photos_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'storage'
as $function$
declare
  v_type text := lower(coalesce(new.metadata->>'mimetype', ''));
  v_size bigint := coalesce((new.metadata->>'size')::bigint, 0);
  v_video boolean;
begin
  if new.bucket_id <> 'chat-photos' then
    return new;
  end if;

  v_video := v_type in (
    'video/mp4', 'video/quicktime', 'video/3gpp', 'video/x-matroska',
    'application/mp4'
  );

  -- tipe diizinkan: gambar, audio, video story
  if not v_video and v_type not in (
    'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
    'audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/mpeg', 'audio/mp3'
  ) then
    raise exception 'Tipe file tidak diizinkan: %', v_type
      using errcode = 'check_violation';
  end if;

  -- batas: video 20 MB, lainnya 8 MB
  if v_video and v_size > 20 * 1024 * 1024 then
    raise exception 'Ukuran video melebihi batas 20 MB (%).', v_size
      using errcode = 'check_violation';
  end if;
  if not v_video and v_size > 8 * 1024 * 1024 then
    raise exception 'Ukuran file melebihi batas 8 MB (%).', v_size
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

comment on function public.chat_photos_guard() is
  'Guard BEFORE INSERT/UPDATE storage.objects bucket chat-photos: whitelist tipe (gambar/audio/video) + limit 8 MB (video 20 MB).';
