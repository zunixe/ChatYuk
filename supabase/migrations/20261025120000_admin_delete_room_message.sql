-- ============================================================
-- ChatYuk: Admin hapus pesan SIAPA PUN di room (global & grup)
--
-- RLS `messages_update_own` hanya izinkan sender_id = auth.uid.
-- Admin (email tunggal zunixe@gmail.com) butuh bisa soft-delete pesan
-- user lain — lewat RPC SECURITY DEFINER yang menegakkan gate email
-- admin di server (user biasa & anon DIBLOKIR, klien jahat tak bisa
-- memanggilnya).
--
-- Soft-delete (is_deleted = true) — isi/media tetap di DB (audit),
-- tampilan klien merender "Pesan dihapus" dan menyembunyikan isi.
-- Idempoten: hapus pesan yang sudah terhapus tetap ok.
-- ============================================================

create or replace function public.admin_delete_room_message(
  p_message_id bigint,
  p_deleted boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rows int;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update public.messages
    set is_deleted = p_deleted
    where id = p_message_id;

  get diagnostics rows = row_count;

  return jsonb_build_object('ok', rows > 0, 'rows', rows);
end;
$$;

revoke execute on function public.admin_delete_room_message(bigint, boolean) from public, anon;
grant execute on function public.admin_delete_room_message(bigint, boolean) to authenticated, service_role;
