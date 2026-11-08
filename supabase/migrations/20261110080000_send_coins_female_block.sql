-- menyentuh: send_coins
-- 2026-11-07: user perempuan TIDAK BISA mengirim koin (keputusan user —
-- sama dengan send_gift 20261110070000). Mencegah perempuan memindahkan
-- penghasilan (`earned`, bisa ditarik) ke akun lain. Body = versi live
-- (20261110050000_promo_bonus_spend) + satu blok `my_gender = 'female'`.
CREATE OR REPLACE FUNCTION public.send_coins(p_chat_id text, p_receiver_id uuid, p_amount integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid(); am_registered boolean; remaining int;
  my_name text; my_gender text; points_on boolean; tx_max int;
  v_cut_pct int; v_cut int; v_net int;
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  select points_enabled into points_on from app_settings where id = 'global';
  if points_on is false and coalesce(auth.email(), '') <> 'zunixe@gmail.com' then
    raise exception 'Points system disabled';
  end if;

  if p_amount is null or p_amount < 5 or p_amount > 1000 then raise exception 'Invalid amount'; end if;
  if p_receiver_id = uid then raise exception 'Cannot send to self'; end if;

  select coin_tx_max_per_hour into tx_max from app_settings where id = 'global';
  if (select count(*) from coin_ledger
      where user_id = uid and type in ('coin_sent','gift_sent')
      and created_at > now() - interval '1 hour') >= coalesce(tx_max, 30) then
    raise exception 'Too many transactions';
  end if;

  select is_registered, nickname, gender into am_registered, my_name, my_gender
    from public.profiles where id = uid;
  if am_registered is not true then raise exception 'Sender must be registered'; end if;
  -- 2026-11-07: perempuan tidak bisa kirim koin (cegah pindah penghasilan).
  if my_gender = 'female' then
    raise exception 'Female cannot send coins' using errcode = '42501';
  end if;

  if not exists (select 1 from public.private_chats pc
    where pc.chat_id = p_chat_id and uid = any (pc.participants)
      and p_receiver_id = any (pc.participants)) then
    raise exception 'Not a chat participant'; end if;

  if exists (select 1 from public.blocks b
    where (b.blocker_id = uid and b.blocked_id = p_receiver_id)
       or (b.blocker_id = p_receiver_id and b.blocked_id = uid)) then
    raise exception 'Blocked'; end if;

  -- B1: potongan platform (default 30%). Penerima menerima NET ke
  -- `earned` — masih bisa di-withdraw, tapi hasil "pencucian" send_coins
  -- kini dipotong seperti gift sehingga refund-fraud tidak lagi gratis.
  select coalesce(coin_send_cut_pct, 30) into v_cut_pct
    from app_settings where id = 'global';

  -- Koin beli/penghasilan dulu; male boleh menambal dengan bonus
  -- (×multiplier, plafon promo) — ledger_spend_promo (2026-11-10).
  remaining := public.ledger_spend_promo(uid, 'coin_sent', p_amount, p_chat_id,
    p_receiver_id, 100 - v_cut_pct);
  v_cut := (p_amount * v_cut_pct) / 100;
  v_net := p_amount - v_cut;

  perform public.ledger_credit(p_receiver_id, 'earned', 'coin_received', v_net,
    p_chat_id, jsonb_build_object('from', uid,
      'gross', p_amount, 'cut', v_cut, 'pct', v_cut_pct));

  if v_cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
    values ('coin_send_cut', v_cut, uid, p_receiver_id, p_chat_id,
            jsonb_build_object('gross', p_amount, 'pct', v_cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount)
    values (uid, 'coin_sent', -p_amount), (p_receiver_id, 'coin_received', v_net);

  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_chat_id, uid, coalesce(my_name, 'Anon'), coalesce(my_gender, 'other'),
            p_amount::text, 'coin', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining, 0),
    'sent', p_amount, 'received', v_net, 'cut_pct', v_cut_pct);
end; $function$;
