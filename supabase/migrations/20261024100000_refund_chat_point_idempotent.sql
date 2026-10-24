-- refund_chat_point: idempoten + jendela waktu (REVIEW_2026-10-24 SEC-02).
--
-- Bug: versi 20260819000000 me-refund baris `spend_chat` TERAKHIR untuk
-- msg_type tanpa menandai bahwa baris itu sudah di-refund. Memanggil RPC
-- berulang (REST /rpc/refund_chat_point) = refund berulang dari spend yang
-- sama → saldo naik tanpa batas. Tidak mengecek `points_enabled` juga, jadi
-- spend lama (sebelum poin dimatikan) tetap bisa di-"refund" berkali-kali.
--
-- Fix:
--   1. Hanya spend ≤ 10 menit terakhir yang boleh di-refund (refund dipakai
--      klien segera setelah kirim gagal / outbox menyerah).
--   2. Setiap baris refund menyimpan `metadata.refund_of` = id baris spend
--      asal; spend yang sudah punya refund dilewati.
--   3. Unique index parsial (user_id, refund_of) di baris `spend_refund`
--      sebagai jaring pengaman race (dua panggilan paralel).
--   4. Advisory lock per user selama transaksi.
--
-- SAFE: hanya mengganti body public.refund_chat_point (bukan FROZEN) + index
--       baru pada coin_ledger (0 baris spend_refund saat ini → tidak bisa
--       bentrok). Kontrak RPC (arg msg_type text → int saldo) tetap sama.
--       Fitur terdampak: refund poin saat kirim pesan/foto/file gagal
--       (chat_send_mixin, chat_outbox_mixin, chat_photo_send_mixin,
--       chat_file_send_mixin).

create unique index if not exists coin_ledger_refund_once
  on public.coin_ledger (user_id, (metadata->>'refund_of'))
  where type = 'spend_refund';

create or replace function public.refund_chat_point(msg_type text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_latest timestamptz;
begin
  if v_uid is null then
    return 0;
  end if;

  perform pg_advisory_xact_lock(hashtext('refund_chat_point:' || v_uid::text));

  -- Satu spend bisa terdiri dari beberapa baris (split bucket) dengan
  -- created_at sama (satu transaksi). Ambil grup terbaru yang BELUM di-refund.
  select l.created_at into v_latest
    from public.coin_ledger l
   where l.user_id = v_uid
     and l.type = 'spend_chat'
     and l.ref_id = msg_type
     and l.created_at > now() - interval '10 minutes'
     and not exists (
       select 1 from public.coin_ledger r
        where r.user_id = v_uid
          and r.type = 'spend_refund'
          and r.metadata->>'refund_of' = l.id::text
     )
   order by l.created_at desc
   limit 1;

  if v_latest is null then
    return public.wallet_sync_points(v_uid);
  end if;

  insert into public.coin_ledger (user_id, bucket, type, amount, ref_id, metadata)
  select l.user_id, l.bucket, 'spend_refund', -l.amount, l.ref_id,
         jsonb_build_object('refunded_msg_type', msg_type, 'refund_of', l.id::text)
    from public.coin_ledger l
   where l.user_id = v_uid
     and l.type = 'spend_chat'
     and l.ref_id = msg_type
     and l.created_at = v_latest
     and not exists (
       select 1 from public.coin_ledger r
        where r.user_id = v_uid
          and r.type = 'spend_refund'
          and r.metadata->>'refund_of' = l.id::text
     )
  on conflict do nothing;

  return public.wallet_sync_points(v_uid);
end;
$$;

revoke execute on function public.refund_chat_point(text) from public, anon;
grant execute on function public.refund_chat_point(text) to authenticated, service_role; -- SAFE: grant sama persis dengan versi 20260819000000 (klien authenticated memanggil refund); tidak menyentuh tabel bersama.
