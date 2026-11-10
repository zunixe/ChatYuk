-- Promo (bonus menambal ×3) untuk akun ADMIN/DEV.
--
-- Latar: `_promo_payer_ok` memblokir pemakaian bonus bila install_id
-- perangkat dipakai >1 akun (anti-farming bonus). Akun admin/dev memang
-- punya banyak akun test di satu HP (admin + dummy + akun uji), jadi guard
-- itu membuat bonus TIDAK PERNAH bisa dipakai admin — padahal aturan
-- YukCoin: bonus boleh menambal harga ×3 (ledger_spend_promo).
--
-- Perbaikan: pemanggil yang email-nya admin (`_email_is_admin`) dan
-- p_payer = auth.uid() melewati guard perangkat; sisa syarat (budget promo)
-- tetap berlaku. Pola sama dengan bypass `points_enabled` di `send_coins`.
--
-- Menyentuh: _promo_payer_ok (bukan FROZEN). Sifat: additive (hanya
-- menambah cabang early-return untuk admin).

CREATE OR REPLACE FUNCTION public._promo_payer_ok(p_payer uuid, p_recipient uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_gender text;
  v_reg boolean;
begin
  if p_payer is null then
    return false;
  end if;
  -- Admin/dev: banyak akun test di satu HP → guard device-bersama tidak
  -- relevan (bukan pola farming). Hanya bila memeriksa dirinya sendiri.
  if p_payer = auth.uid() and public._email_is_admin() then
    return public.promo_budget_left_idr() > 0;
  end if;
  if (select points_enabled from public.app_settings where id = 'global') is false then
    return false;
  end if;
  select gender, coalesce(is_registered, false) into v_gender, v_reg
    from public.profiles where id = p_payer;
  if v_gender is distinct from 'male' or not v_reg then
    return false;
  end if;
  if not exists (select 1 from public.user_devices
                  where user_id = p_payer and install_id <> 'unknown') then
    return false;
  end if;
  -- Device dipakai akun lain (termasuk penerima / akun anonim) → tidak.
  if exists (select 1 from public.user_devices d1
               join public.user_devices d2 on d2.install_id = d1.install_id
              where d1.user_id = p_payer and d2.user_id <> p_payer
                and d1.install_id <> 'unknown') then
    return false;
  end if;
  return public.promo_budget_left_idr() > 0;
end;
$function$
