-- refund_chat_point: idempoten + jendela waktu + kill-switch (REVIEW_2026-10-24 SEC-02, P0)
--
-- Bug: versi 20260819000000 me-refund baris `spend_chat` TERAKHIR untuk
-- `msg_type` tanpa menandai bahwa baris itu sudah di-refund. Memanggil RPC
-- berulang (REST /rpc/refund_chat_point) = refund berulang dari spend yang
-- sama -> saldo naik tanpa batas -> fitur berbayar gratis & nilai top-up
-- Google Play Billing tergerus. Versi itu juga tidak mengecek
-- `points_enabled`, jadi spend lama bisa di-"refund" berkali-kali.
--
-- Perbaikan ini MENGGABUNGKAN dua rancangan yang sempat dibuat terpisah
-- (20261024100000 oleh sesi lain + 20261024140000 yang sudah live):
--   1. Jendela refund 10 menit (hanya untuk kegagalan kirim yang wajar).
--   2. `metadata.refund_of` = id baris spend asal; spend yang sudah punya
--      refund dilewati.
--   3. UNIQUE INDEX parsial (user_id, refund_of) -> jaring pengaman bila dua
--      panggilan paralel lolos cek.
--   4. `pg_advisory_xact_lock` per user -> serialisasi, cegah race sebelum
--      insert (unique index saja akan melempar error, bukan "skip").
--   5. Kill-switch `points_enabled`: bila poin nonaktif tidak ada debit,
--      jadi refund tidak boleh menulis apa pun (hanya sync saldo).
--   6. Grup spend diambil per `created_at` (satu transaksi ledger bisa
--      memecah bucket earned/bonus dengan created_at sama).
--
-- Aman untuk data historis: live punya 0 baris `spend_refund`
-- (diverifikasi 2026-10-24) -> unique index tidak bisa bentrok.
--
-- SAFE: hanya mengganti body public.refund_chat_point (bukan FROZEN) + 1 index
--       baru pada coin_ledger. Kontrak RPC (arg msg_type text -> int saldo)
--       tetap sama; grant execute tetap authenticated/service_role.
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
as $function$
declare
  v_uid     uuid := auth.uid();
  v_enabled boolean;
  v_latest  timestamptz;
begin
  if v_uid is null then
    return 0;
  end if;

  -- Kill-switch: tanpa poin aktif tidak ada debit -> tidak ada yang direfund.
  select points_enabled into v_enabled
    from public.app_settings where id = 'global';
  if coalesce(v_enabled, false) is not true then
    return public.wallet_sync_points(v_uid);
  end if;

  -- Serialisasi per user: dua panggilan paralel tidak boleh sama-sama lolos
  -- pengecekan "belum pernah direfund".
  perform pg_advisory_xact_lock(hashtext('refund_chat_point:' || v_uid::text));

  -- Grup spend terbaru yang BELUM di-refund, dalam jendela 10 menit.
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
$function$;

revoke execute on function public.refund_chat_point(text) from public, anon;
-- SAFE: grant sama persis dengan versi sebelumnya (klien authenticated memanggil
--       refund saat kirim gagal); tidak menyentuh tabel/policy bersama.
grant execute on function public.refund_chat_point(text) to authenticated, service_role;
