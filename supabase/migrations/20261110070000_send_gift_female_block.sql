-- menyentuh: send_gift
-- 2026-11-07: user perempuan TIDAK BISA mengirim gift (permintaan user:
-- "diperempuan ga usah bisa kirim gift"). App sudah menyembunyikan ikon gift
-- di private chat untuk perempuan; guard ini menutup jalur RPC langsung.
-- Gender NULL/lainnya tetap boleh (sama dengan app). Satu-satunya perubahan
-- dari versi live (20261110050000_promo_bonus_spend) = blok `my_gender`.
CREATE OR REPLACE FUNCTION public.send_gift(p_chat_id text, p_receiver_id uuid, p_gift_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  g record; points_on boolean; cut_pct int; tx_max int;
  my_name text; my_gender text; am_registered boolean;
  n int; cut int; net int;
  paid int; remaining int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  -- 2026-11-10: serialkan debit per user (sama dgn ledger_spend_paid dst);
  -- juga menutup balapan cek batas transaksi/jam.
  perform pg_advisory_xact_lock(hashtext('wallet:' || uid::text));
  if p_receiver_id = uid then raise exception 'Cannot gift self'; end if;
  select points_enabled, coalesce(gift_cut_pct,30)
    into points_on, cut_pct from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;
  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;
  if my_gender = 'female' then
    raise exception 'Female cannot send gift' using errcode = '42501';
  end if;
  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;
  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins;
  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;
  if exists (select 1 from public.blocks b
      where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
         or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- 2026-10-31: gift WAJIB pakai koin beli/penghasilan (topup + earned).
  -- Koin gratis (`bonus`) TIDAK boleh dipakai — mencegah koin gratis male
  -- berubah menjadi saldo withdrawable female (rugi platform).
  -- 2026-11-10: male boleh menambal dengan bonus (harga ×multiplier,
  -- plafon promo) — ledger_spend_promo.
  paid := public.yukcoin_spendable(uid, p_receiver_id, 100 - cut_pct);

  if paid < n then
    raise exception 'Gift membutuhkan koin beli/penghasilan (top-up dulu)'
      using errcode = '22023';
  end if;

  remaining := public.ledger_spend_promo(uid, 'gift_sent', n, p_chat_id,
    p_receiver_id, 100 - cut_pct);

  -- Platform ambil cut; penerima SELALU bucket `earned`.
  cut := (n * cut_pct) / 100;
  net := n - cut;

  if net > 0 then
    perform public.ledger_credit(p_receiver_id, 'earned', 'gift_recv', net,
      p_chat_id, jsonb_build_object('gift', p_gift_id, 'from', uid, 'tier', 'paid'));
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, p_receiver_id, p_chat_id,
              jsonb_build_object('gift', p_gift_id, 'gross', n, 'net', net, 'pct', cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n, jsonb_build_object('gift', p_gift_id, 'tier', 'paid')),
           (p_receiver_id, 'gift_recv', net,
            jsonb_build_object('gift', p_gift_id, 'tier', 'paid'));

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'gross', n, 'net', net, 'cut', cut, 'tier', 'paid');
end; $function$;
