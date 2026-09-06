-- ============================================================
-- ChatYuk — Room Gift (live room ala streaming)
--
-- Gift dari member/penonton private room → host (owner room).
-- Pola wallet identik send_gift (phase3): debit bucket
-- bonus→topup→earned, platform cut, kredit net ke owner dengan
-- lineage proporsional, log platform_revenue + point_events,
-- pesan bukti type='gift' di messages (room) → realtime ke semua.
--
-- Qty 1..20 untuk kombo panel (satu debit, satu bubble).
-- ============================================================

-- 1. Izinkan type 'gift' di messages (room)
alter table public.messages
  drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check
  check (type = any (array['text'::text,'image'::text,'view_once'::text,
    'view_once_expired'::text,'voice'::text,'gift'::text]));

-- 2. RPC: send_room_gift(room_id, gift_id, qty)
create or replace function public.send_room_gift(
  p_room_id text, p_gift_id text, p_qty int default 1
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  g record; r record; points_on boolean; cut_pct int;
  my_name text; my_gender text;
  b int; t int; e int; need int;
  pay_bonus int := 0; pay_topup int := 0; pay_earned int := 0;
  n int; cut int; net int;
  earn_src int; recv_earned int; recv_bonus int; remaining int;
  host_id uuid;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 20 then
    raise exception 'Invalid qty';
  end if;

  select points_enabled, coalesce(gift_cut_pct,30) into points_on, cut_pct
    from app_settings where id = 'global';
  if points_on is false then raise exception 'Points system disabled'; end if;

  select * into g from gift_catalog where id = p_gift_id and active = true;
  if not found then raise exception 'Invalid gift'; end if;
  n := g.coins * p_qty;

  -- Room harus private (live room), aktif, dan punya owner (host)
  select * into r from rooms where id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  if r.is_private is not true then raise exception 'Not a live room'; end if;
  if r.expires_at is not null and r.expires_at <= now() then
    raise exception 'Room expired';
  end if;
  host_id := r.owner_id;
  if host_id is null then raise exception 'Room has no host'; end if;
  if host_id = uid then raise exception 'Cannot gift self'; end if;

  -- Pengirim harus member room atau host-nya sendiri (tidak relevan, tapi aman)
  if not exists (select 1 from room_members rm
      where rm.room_id = p_room_id and rm.user_id = uid)
    and not exists (select 1 from rooms r2
      where r2.id = p_room_id and r2.owner_id = uid) then
    raise exception 'Not a room member';
  end if;

  -- saldo & porsi bucket pengirim
  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = uid;
  if (b + t + e) < n then raise exception 'Not enough points'; end if;

  need := n;
  pay_bonus  := least(b, need); need := need - pay_bonus;
  pay_topup  := least(t, need); need := need - pay_topup;
  pay_earned := least(e, need); need := need - pay_earned;

  if pay_bonus > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'bonus','gift_sent',-pay_bonus,p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'room',true));
  end if;
  if pay_topup > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'topup','gift_sent',-pay_topup,p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'room',true));
  end if;
  if pay_earned > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id,metadata)
      values (uid,'earned','gift_sent',-pay_earned,p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'room',true));
  end if;
  remaining := public.wallet_sync_points(uid);

  -- platform cut + net ke host (lineage proporsional, pola phase3)
  cut := (n * cut_pct) / 100;
  net := n - cut;

  earn_src := pay_topup + pay_earned;
  if net <= 0 then
    recv_earned := 0; recv_bonus := 0;
  elsif earn_src = 0 then
    recv_earned := 0; recv_bonus := net;
  elsif pay_bonus = 0 then
    recv_earned := net; recv_bonus := 0;
  else
    recv_earned := (net * earn_src) / n;
    recv_bonus  := net - recv_earned;
  end if;

  if recv_earned > 0 then
    perform public.ledger_credit(host_id,'earned','gift_recv',recv_earned,p_room_id,
      jsonb_build_object('gift',p_gift_id,'qty',p_qty,'from',uid));
  end if;
  if recv_bonus > 0 then
    perform public.ledger_credit(host_id,'bonus','gift_recv',recv_bonus,p_room_id,
      jsonb_build_object('gift',p_gift_id,'qty',p_qty,'from',uid));
  end if;

  if cut > 0 then
    insert into platform_revenue(source, amount, from_user, to_user, ref_id, metadata)
      values ('gift_cut', cut, uid, host_id, p_room_id,
              jsonb_build_object('gift',p_gift_id,'qty',p_qty,'gross',n,'net',net,'pct',cut_pct));
  end if;

  insert into public.point_events (user_id, event, amount, metadata)
    values (uid, 'gift_sent', -n, jsonb_build_object('gift',p_gift_id,'qty',p_qty)),
           (host_id, 'gift_recv', net, jsonb_build_object('gift',p_gift_id,'qty',p_qty));

  -- pesan bukti gift di room feed (realtime ke semua penonton)
  select nickname, gender into my_name, my_gender from public.profiles where id = uid;
  insert into public.messages (room_id, sender_id, sender_name, sender_gender, text, type, image_data)
    values (p_room_id, uid, coalesce(my_name,'Anon'), coalesce(my_gender,'other'),
            p_gift_id, 'gift', '');

  return jsonb_build_object('ok', true, 'points', coalesce(remaining,0),
    'gift', p_gift_id, 'qty', p_qty, 'gross', n, 'net', net, 'cut', cut);
end; $$;

revoke execute on function public.send_room_gift(text, text, int) from public, anon;
grant execute on function public.send_room_gift(text, text, int) to authenticated;
