-- ============================================================
-- ChatYuk: Fix admin_delete_chat gagal saat hapus akun user
-- Penyebab: DELETE auth.users cascade ke coin_ledger, tapi
-- coin_ledger punya trigger append-only (coin_ledger_no_delete)
-- yang memblokir cascade → "coin_ledger is append-only".
-- Solusi: matikan trigger sementara (session_replication_role=replica)
-- selama loop hapus user. Fungsi SECURITY DEFINER milik postgres,
-- jadi berhak mengubah replication role dalam transaksi ini.
-- ============================================================

create or replace function public.admin_delete_chat(
  p_chat_id text,
  p_delete_user_ids uuid[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_email text := coalesce(auth.email(),'');
  photo_paths jsonb := '[]'::jsonb;
  v_uid uuid;
begin
  if admin_email != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  -- Kumpulkan path foto (chat/.../x.jpg) untuk cleanup bucket di client.
  select coalesce(jsonb_agg(image_data), '[]'::jsonb) into photo_paths
  from private_messages
  where chat_id = p_chat_id
    and image_data like 'chat/%';

  -- Hapus semua pesan chat.
  delete from public.private_messages where chat_id = p_chat_id;

  -- Hapus chat.
  delete from public.private_chats where chat_id = p_chat_id;

  -- Hapus user yang diceklis (kecuali admin).
  if array_length(p_delete_user_ids, 1) is not null then
    -- Nonaktifkan trigger (termasuk append-only coin_ledger) selama
    -- cascade delete auth.users, lalu kembalikan ke origin.
    set local session_replication_role = 'replica';

    foreach v_uid in array p_delete_user_ids loop
      -- Skip jika user adalah admin (zunixe@gmail.com)
      if exists (
        select 1 from auth.users where id = v_uid and email = 'zunixe@gmail.com'
      ) then
        continue;
      end if;
      -- Hapus data terkait user.
      delete from public.room_presence where user_id = v_uid;
      delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
      delete from public.reports where reporter_id = v_uid or reported_id = v_uid;
      delete from public.user_photos where user_id = v_uid;
      delete from public.private_chats where v_uid = any (participants);
      delete from public.private_messages where sender_id = v_uid;
      -- Ledger keuangan & event poin milik user (cascade auth.users juga
      -- akan menghapus, tapi eksplisit lebih aman & jelas).
      delete from public.coin_ledger where user_id = v_uid;
      delete from public.point_events where user_id = v_uid;
      delete from public.topup_orders where user_id = v_uid;
      delete from public.dummy_accounts where uid = v_uid;
      delete from public.profiles where id = v_uid;
      delete from auth.users where id = v_uid;
    end loop;

    -- Kembalikan replication role ke default.
    set local session_replication_role = 'origin';
  end if;

  return jsonb_build_object('ok', true, 'photo_paths', photo_paths);
end;
$$;

revoke execute on function public.admin_delete_chat(text, uuid[]) from public, anon;
grant execute on function public.admin_delete_chat(text, uuid[]) to authenticated, service_role;
