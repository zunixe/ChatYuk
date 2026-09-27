-- ============================================================
-- Admin monitor chat: kirim `image_path` + data video supaya admin bisa
-- MELIHAT semua media (foto biasa, video, dan view-once foto/video).
--
-- MASALAH: `admin_get_chat_messages_page` lama:
--   - hanya mengisi `image_data` untuk type view_once/view_once_expired;
--   - TIDAK mengirim `image_path` sama sekali.
-- Akibatnya di monitor admin: foto biasa, video, dan video view-once
-- tampil kosong/tak bisa dimuat (FotoCache butuh path/id yang belum ada).
--
-- PERUBAHAN (tambah key output, bentuk tetap):
--   - 'image_path' : m.image_path  (path storage — foto & video).
--   - 'image_data' : tetap utuh utk view_once/view_once_expired (admin boleh
--     lihat walau sudah kadaluarsa) + video_once/video_once_expired (agar
--     poster/data video view-once ikut terbaca).
--   - 'video_path' : alias image_path utk type video (klien sudah menaruh
--     video di imageData — tetap kirim image_path agar konsisten).
--   - 'is_deleted','edited' ikut dikirim (UI bubble memakainya).
--
-- Guard admin TIDAK berubah (email zunixe). Idempotent (create or replace).
-- Bukan fungsi FROZEN. CARA APPLY: Management API.
-- ============================================================

create or replace function public.admin_get_chat_messages_page(
  p_chat_id text,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'chat_id', m.chat_id,
      'sender_id', m.sender_id,
      'sender_name', m.sender_name,
      'sender_gender', m.sender_gender,
      'text', m.text,
      'type', m.type,
      'is_deleted', m.is_deleted,
      'edited', m.edited,
      -- PATH storage: dipakai admin untuk unduh foto/video (foto biasa &
      -- video tidak lagi kosong di monitor).
      'image_path', m.image_path,
      -- data inline: view-once foto/video tetap utuh (admin boleh lihat
      -- walau sudah kadaluarsa); tipe lain dikosongkan (lazy via path).
      'image_data', case
        when m.type in (
          'view_once','view_once_expired',
          'video_once','video_once_expired'
        ) then m.image_data
        else ''
      end,
      'voice_path', m.voice_path,
      'duration_ms', m.duration_ms,
      'created_at', m.created_at,
      'replied_to_id', m.replied_to_id,
      'replied_to_text', m.replied_to_text,
      'replied_to_sender_name', m.replied_to_sender_name
    ) order by m.created_at desc
  ), '[]'::jsonb) into result
  from (
    select m.*
    from private_messages m
    where m.chat_id = p_chat_id
    order by m.created_at desc
    limit p_limit offset p_offset
  ) m;

  return result;
end;
$function$;
