-- RPC `get_withdraw_config` — setting withdraw untuk kalkulator di app.
-- Dipisah dari Fase 2 karena baru diperlukan saat Flutter butuh preview fee.

CREATE OR REPLACE FUNCTION public.get_withdraw_config()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'rate', coalesce(withdraw_rate_idr, 7),
        'min_coins', coalesce(withdraw_min_coins, 1500),
        'fee_pct', coalesce(withdraw_fee_pct, 5),
        'fee_min_idr', coalesce(withdraw_fee_min_idr, 1000),
        'max_per_day', coalesce(withdraw_max_per_day, 3),
        'min_interval_hours', coalesce(withdraw_min_interval_hours, 1),
        'min_account_age_hours', coalesce(withdraw_min_account_age_hours, 72)
    ) INTO result
    FROM public.app_settings WHERE id = 'global';

    RETURN coalesce(result, jsonb_build_object(
        'rate', 7, 'min_coins', 1500, 'fee_pct', 5, 'fee_min_idr', 1000,
        'max_per_day', 3, 'min_interval_hours', 1, 'min_account_age_hours', 72));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_withdraw_config() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_withdraw_config() TO authenticated, service_role;
