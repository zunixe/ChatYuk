-- 2026-11-04b: `match_search` (fee pair Random Match) boleh debit bucket
-- `topup` — sebelumnya hanya earned+bonus.
--
-- Bug nyata yang ditemukan saat test precheck paid>=12: male yang SALDO
-- topup-only (beli koin, belum pernah earned/bonus) selalu gagal bayar
-- fee pair → `_spend_yukcoin_core` melempar 'YukCoin tidak cukup' →
-- joiner female me-skip dia, dan kalau dia joiner → no_funds. Efeknya:
-- user BERBAYAR tidak pernah bisa match.
--
-- Kenapa topup aman di sini: fee match_search murni masuk platform_revenue
-- (tidak ada penerima → tidak ada jalur bonus→earned/withdrawable, jadi
-- tak ada risiko pencucian seperti di gift). Debit order: bonus → topup →
-- earned — koin gratis terbakar duluan, saldo beli/withdrawable dijaga.
--
-- Fitur 'gift'/'gift_sent' di whitelist yang sama TETAP earned+bonus
-- (perilaku lama, tidak diubah — jalur gift nyata lewat send_gift yang
-- punya aturan paid-only sendiri).
--
-- menyentuh: _spend_yukcoin_core

create or replace function public._spend_yukcoin_core(
  p_user uuid, p_feature text, p_amount integer,
  p_ref text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e int; b int; t int; need int; take int; tier text;
begin
  -- INTERNAL ONLY — dipanggil dari fungsi trusted SECURITY DEFINER
  -- (mis. random_match_join). Auth gate ada di wrapper spend_yukcoin.
  -- REVOKE dari public/anon/authenticated di bagian grant.
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  -- Kill-switch ekonomi: points_enabled=false → free (pola 110013).
  if (select points_enabled from app_settings where id = 'global') is false then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  -- 2026-10-31: hanya GIFT + biaya pencarian MATCH yang memotong poin.
  -- undo, edit, slot foto, mode hantu, filter, nearby → GRATIS.
  if p_feature not in ('gift','gift_sent','match_search') then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  -- Audit: female tidak pernah keluar koin.
  if p_feature = 'match_search'
     and (select gender from public.profiles where id = p_user) = 'female' then
    return jsonb_build_object('tier', 'free', 'charged', 0,
      'remaining', public.yukcoin_total(p_user), 'free', true);
  end if;

  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0),
         coalesce(sum(amount) filter (where bucket = 'topup'), 0)
    into e, b, t
    from public.coin_ledger
   where user_id = p_user;

  -- 2026-11-04b: `match_search` = fee ke platform (tanpa penerima) → seluruh
  -- bucket boleh dipakai termasuk `topup` (tadinya terlewat → user topup-
  -- only tak bisa match). 'gift'/'gift_sent' tetap earned+bonus.
  if p_feature = 'match_search' then
    if (b + t + e) < p_amount then
      raise exception 'YukCoin tidak cukup';
    end if;
    need := p_amount;
    -- bonus → topup → earned: koin gratis terbakar duluan.
    take := least(b, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
    if need > 0 then
      take := least(t, need);
      if take > 0 then
        insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
          values (p_user, 'topup', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
        need := need - take;
      end if;
    end if;
    if need > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'earned', p_feature, -need, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := 0;
    end if;
    tier := case when b >= p_amount then 'bonus'
                 when b + t >= p_amount then 'mixed' else 'mixed' end;
  else
    if (e + b) < p_amount then
      raise exception 'YukCoin tidak cukup';
    end if;

    need := p_amount;
    take := least(e, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'earned', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
    if need > 0 then
      take := least(b, need);
      if take > 0 then
        insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
          values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
        need := need - take;
      end if;
    end if;
    tier := case when e >= p_amount then 'earned' else 'mixed' end;
  end if;

  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (p_user, p_feature, p_amount, p_ref, coalesce(p_meta, '{}'::jsonb));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, p_feature, -p_amount,
            jsonb_build_object('feature', p_feature, 'ref', p_ref, 'tier', tier));

  -- Audit: fee pencarian match hangus (tidak ada penerima) → revenue platform.
  if p_feature = 'match_search' then
    insert into public.platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('match_search', p_amount, p_user, null, p_ref,
              jsonb_build_object('kind', 'search_fee'));
  end if;

  return jsonb_build_object('tier', tier, 'charged', p_amount,
    'remaining', public.yukcoin_total(p_user));
end;
$function$;
