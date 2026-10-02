-- ============================================================
-- ChatYuk — Batalkan (cancel) friend request yang SUDAH dikirim.
--
-- Sebelumnya Outbox hanya menampilkan status "Terkirim" tanpa cara
-- membatalkan. RPC ini menghapus request pending milik PENGIRIM
-- (hanya pengirim yang boleh membatalkan requestnya sendiri).
--
-- Aman & idempoten: request yang sudah accepted/rejected TIDAK dihapus
-- (status <> 'pending' → no-op, kembalikan ok=false alasan 'not_pending').
-- ============================================================

create or replace function public.cancel_friend_request(p_request_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  req record;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select * into req
    from public.friend_requests
   where id = p_request_id and from_id = me;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- Hanya request PENDING yang bisa dibatalkan. Bila sudah direspons,
  -- biarkan (histori tetap) — bukan hak pengirim membatalkannya.
  if req.status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'not_pending',
                              'status', req.status);
  end if;

  delete from public.friend_requests where id = p_request_id;

  return jsonb_build_object('ok', true);
end;
$fn$;

revoke execute on function public.cancel_friend_request(bigint) from public, anon;
grant execute on function public.cancel_friend_request(bigint) to authenticated, service_role;
