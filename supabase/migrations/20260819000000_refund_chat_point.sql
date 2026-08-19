-- ============================================================
-- ChatYuk — refund_chat_point: balikkan biaya chat saat kirim gagal
-- (upload storage gagal / blocked / network). Mencegah koin hilang
-- percuma padahal pesan tidak terkirim.
--
-- Cara kerja: cari batch ledger 'spend_chat' terakhir untuk msg_type
-- ini, lalu credit balik ke bucket masing-masing. Semua entry dalam
-- satu panggilan ledger_spend berbagi created_at yang sama (now()
-- stabil per transaksi), jadi aman dikelompokkan.
-- ============================================================

create or replace function public.refund_chat_point(msg_type text)
returns int language plpgsql security definer set search_path = public as $$
declare
  latest timestamptz;
  r int;
begin
  select created_at into latest
    from public.coin_ledger
    where user_id = auth.uid()
      and type = 'spend_chat'
      and ref_id = msg_type
    order by created_at desc
    limit 1;

  if latest is null then
    return public.wallet_sync_points(auth.uid());
  end if;

  insert into public.coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
  select user_id, bucket, 'spend_refund', -amount, ref_id,
         jsonb_build_object('refunded_msg_type', msg_type)
    from public.coin_ledger
    where user_id = auth.uid()
      and type = 'spend_chat'
      and ref_id = msg_type
      and created_at = latest;

  get diagnostics r = row_count;
  if r = 0 then
    return public.wallet_sync_points(auth.uid());
  end if;

  return public.wallet_sync_points(auth.uid());
end; $$;

revoke execute on function public.refund_chat_point(text) from public, anon;
grant execute on function public.refund_chat_point(text) to authenticated, service_role;
