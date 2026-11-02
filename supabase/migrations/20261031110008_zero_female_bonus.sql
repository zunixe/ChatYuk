-- ══════════════════════════════════════════════════════════════════════
-- Nolkan koin `bonus` milik SEMUA user female.
--
-- Konteks: bonus daftar (`signup` 50 koin) diberikan SEBELUM aturan
-- "bonus hanya untuk male" (2026-10-31). Female seharusnya tidak punya
-- koin gratis — penghasilannya murni dari aktivitas male (bucket `earned`).
--
-- `coin_ledger` melarang DELETE/UPDATE (audit trail), jadi saldo dinolkan
-- dengan entri KOMPENSASI negatif (type `female_bonus_reset`). Trigger
-- `trg_coin_ledger_balance` otomatis menyesuaikan `profiles.bonus_balance`
-- dan `profiles.points`.
--
-- Hanya bucket `bonus` yang disentuh. `earned` & `topup` TIDAK berubah.
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_zero_female_bonus(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_admin text := coalesce(auth.email(), '');
  rec record;
  v_sum_bonus bigint := 0;
  v_users int := 0;
  v_applied int := 0;
begin
  if v_admin <> 'zunixe@gmail.com'
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and auth.uid() is not null then
    raise exception 'NOT_ADMIN: hanya admin';
  end if;

  for rec in
    select p.id, p.nickname,
           coalesce((select sum(amount) from public.coin_ledger
                      where user_id = p.id and bucket = 'bonus'), 0) as bonus
      from public.profiles p
     where p.gender = 'female'
     order by p.id
  loop
    if rec.bonus > 0 then
      v_users := v_users + 1;
      v_sum_bonus := v_sum_bonus + rec.bonus;
      if not p_dry_run then
        insert into public.coin_ledger
          (user_id, bucket, type, amount, ref_id, metadata)
        values
          (rec.id, 'bonus', 'female_bonus_reset', -rec.bonus,
           'female_bonus_reset_20261031',
           jsonb_build_object('reason', 'female harus tanpa bonus koin',
                              'before', rec.bonus,
                              'nickname', rec.nickname));
        v_applied := v_applied + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'users_affected', v_users,
    'total_bonus_zeroed', v_sum_bonus,
    'entries_inserted', v_applied
  );
end;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_zero_female_bonus(boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_zero_female_bonus(boolean) TO authenticated, service_role;

-- ── Jalankan (bukan dry run) ──
-- Idempoten: user yang bonus-nya sudah 0 dilewati, jadi aman dijalankan ulang.
select public.admin_zero_female_bonus(false);
