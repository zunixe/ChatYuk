-- ============================================================
-- 123000 — Publish feature flag `call_billing` (billing per-menit ON)
-- ============================================================
-- Keputusan produk: billing per-menit berlaku untuk SEMUA user,
-- bukan hanya admin (bypass zunixe@gmail.com di feature_enabled_for).
-- Match (kind='random'): menit ke-1 gratis, mulai 120 dtk = tarif
-- video. Call biasa: tarif per-menit dari app_settings.
-- ============================================================

UPDATE public.app_settings
   SET feature_flags = feature_flags
       || '{"call_billing":{"published":true}}'::jsonb
 WHERE id = 'global';
