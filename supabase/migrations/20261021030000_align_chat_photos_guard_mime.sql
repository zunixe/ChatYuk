-- SELARASKAN guard MIME lama dengan allowlist bucket.
--
-- Masalah: `public.chat_photos_guard()` (trigger `trg_chat_photos_guard` pada
-- storage.objects) hanya mengizinkan jpeg/png/webp + audio terbatas dan
-- menolak semua selainnya dengan `check_violation` (23514). Akibatnya —
-- TERLEPAS dari `allowed_mime_types` bucket — upload berikut SELALU gagal:
--   * stiker `.tgs`  → application/gzip  (sebelumnya juga image/svg+xml)
--   * stiker `.gif`  → image/gif
--   * dokumen chat   → application/pdf, docx, xlsx, pptx, zip, text/*
--   * video webm     → video/webm
-- Bukti: storage.objects bucket chat-photos folder `stickers` hanya berisi
-- video/mp4 dan folder `chat` hanya video — tidak ada satu pun stiker
-- gambar/`.tgs` maupun dokumen.
--
-- Perbaikan: guard kini mengikuti allowlist bucket (single source of truth).
-- Yang dijaga tetap: video harus video/* (atau application/mp4), file lain
-- tidak boleh video, dan batas ukuran per jenis.
--
-- SAFE: hanya mengganti isi fungsi trigger pada bucket `chat-photos`;
--       tidak menyentuh RLS policy, grant, maupun tabel bersama
--       (profiles/private_chats/private_messages/messages).
create or replace function public.chat_photos_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'storage'
as $function$
declare
  v_type  text := lower(coalesce(new.metadata->>'mimetype', ''));
  v_size  bigint := coalesce((new.metadata->>'size')::bigint, 0);
  v_video boolean;
  v_ok    boolean;
begin
  if new.bucket_id <> 'chat-photos' then
    return new;
  end if;

  -- MIME kosong: tolak (klien selalu mengirim contentType eksplisit).
  if v_type = '' then
    raise exception 'Tipe file kosong (contentType wajib dikirim).'
      using errcode = 'check_violation';
  end if;

  v_video := v_type like 'video/%' or v_type = 'application/mp4';

  -- Sumber kebenaran daftar tipe = `storage.buckets.allowed_mime_types`.
  select coalesce(v_type = any(b.allowed_mime_types), false)
    into v_ok
    from storage.buckets b
   where b.id = 'chat-photos';
  v_ok := coalesce(v_ok, false);

  if not v_ok then
    raise exception 'Tipe file tidak diizinkan: %', v_type
      using errcode = 'check_violation';
  end if;

  -- Batas ukuran: video 50 MB, file lain 20 MB (<= file_size_limit bucket).
  if v_video and v_size > 50 * 1024 * 1024 then
    raise exception 'Ukuran video melebihi batas 50 MB (%).', v_size
      using errcode = 'check_violation';
  end if;
  if not v_video and v_size > 20 * 1024 * 1024 then
    raise exception 'Ukuran file melebihi batas 20 MB (%).', v_size
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;
