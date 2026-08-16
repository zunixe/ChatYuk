-- ============================================================
-- ChatYuk: izinkan type 'coin' di private_messages
--
-- Constraint private_messages_type_check (dibuat manual di dashboard)
-- tadinya hanya mengizinkan text/image/view_once/view_once_expired,
-- sehingga RPC send_coins gagal saat insert pesan bukti transfer.
-- ============================================================

alter table public.private_messages
  drop constraint if exists private_messages_type_check;

alter table public.private_messages
  add constraint private_messages_type_check
  check (type in ('text', 'image', 'view_once', 'view_once_expired', 'coin'));
