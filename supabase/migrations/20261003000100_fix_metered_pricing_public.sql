-- ============================================================
-- ChatYuk — Fix metered_pricing_public setelah kolom kuota-gratis dihapus
--
-- `20261003000000` menghapus app_settings.call_free_minutes_daily, TAPI
-- metered_pricing_public (20261001000000) masih membacanya → error 42703.
-- Perbaiki: kembalikan tanpa call_free_minutes_daily.
--
-- (Tidak menyentuh fungsi FROZEN.) Idempotent.
-- ============================================================

create or replace function public.metered_pricing_public()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return (select jsonb_build_object(
    'call_audio_cost_per_min', call_audio_cost_per_min,
    'call_video_cost_per_min', call_video_cost_per_min,
    'filter_gender_cost', filter_gender_cost,
    'nearby_cost', nearby_cost
  ) from app_settings where id = 'global');
end; $$;
revoke execute on function public.metered_pricing_public() from public, anon;
grant execute on function public.metered_pricing_public() to authenticated, service_role;
