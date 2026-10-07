-- ============================================================
-- Email Marketing — FIX lanjutan (review 2026-10-06, #2)
--
-- Bug: `email_worker_claim` menandai recipient 'sending', tapi CHECK
-- constraint `email_recipients_status_check` TIDAK memuat 'sending'
-- → claim GAGAL (23514) → email tak pernah terkirim.
-- FIX: tambahkan 'sending' ke daftar status yang diizinkan.
-- ============================================================

alter table public.email_recipients
  drop constraint if exists email_recipients_status_check;

alter table public.email_recipients
  add constraint email_recipients_status_check
  check (status in ('pending','sending','sent','delivered','opened',
                    'clicked','bounced','failed','skipped'));
