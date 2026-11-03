-- ============================================================
-- 20261107010000_dana_cooldown_save_account.sql
-- Fase B (lanjutan) — cooldown ganti nomor DANA juga di
-- save_withdraw_account. Tanpa ini user bisa bypass cooldown
-- request_withdraw lewat layar "Ubah akun".
-- Semantik sama: updated_at maju HANYA saat nomor berubah.
-- ============================================================
create or replace function public.save_withdraw_account(p_dana_number text, p_dana_name text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
    v_uid uuid := auth.uid();
    v_num text;
    v_name text;
    v_acc record;
    v_cd_hours int;
    v_free timestamptz;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Normalisasi nomor: buang spasi/strip, wajib 08xx atau 62xx, 10-14 digit.
    v_num := regexp_replace(coalesce(p_dana_number, ''), '[^0-9]', '', 'g');
    IF v_num !~ '^(08|62)[0-9]{8,13}$' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NUMBER');
    END IF;
    -- 62xx → 0xx (format DANA domestik).
    IF v_num LIKE '62%' THEN
        v_num := '0' || substring(v_num from 3);
    END IF;

    v_name := nullif(trim(coalesce(p_dana_name, '')), '');
    IF v_name IS NULL OR length(v_name) < 3 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_NAME');
    END IF;

    -- Cooldown ganti nomor (Fase B): nomor BERBEDA dari tersimpan tak
    -- boleh diganti sebelum cooldown berlalu. Nomor sama/nama saja → bebas.
    SELECT coalesce(withdraw_dana_change_cooldown_hours, 168)
      INTO v_cd_hours
      FROM public.app_settings WHERE id = 'global';
    SELECT * INTO v_acc FROM public.withdraw_accounts WHERE user_id = v_uid;
    IF FOUND AND v_acc.dana_number IS DISTINCT FROM v_num
       AND v_acc.updated_at > now() - make_interval(hours => v_cd_hours) THEN
        v_free := v_acc.updated_at + make_interval(hours => v_cd_hours);
        RETURN jsonb_build_object('ok', false,
            'error', 'DANA_CHANGE_COOLDOWN',
            'cooldown_until', v_free,
            'cooldown_hours', v_cd_hours);
    END IF;

    INSERT INTO public.withdraw_accounts (user_id, dana_number, dana_name, updated_at)
    VALUES (v_uid, v_num, v_name, now())
    ON CONFLICT (user_id) DO UPDATE SET
        dana_number = excluded.dana_number,
        dana_name = excluded.dana_name,
        updated_at = case
          when withdraw_accounts.dana_number is distinct from excluded.dana_number
            then now()
          else withdraw_accounts.updated_at
        end;

    RETURN jsonb_build_object('ok', true,
        'dana_number', v_num, 'dana_name', v_name);
END;
$function$;
