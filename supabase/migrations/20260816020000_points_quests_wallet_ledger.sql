-- ChatYuk: points_quests harus konsisten dengan wallet (get_wallet).
-- Sebelumnya saldo di screen missions ambil profiles.points (cache) yang bisa
-- ketinggalan dari coin_ledger → angka beda dengan profil screen (71 vs 36).
-- Sekarang saldo dihitung dari coin_ledger (source of truth) — sama persis
-- dengan get_wallet.
-- ============================================================

create or replace function public.points_quests(tz_offset_minutes int default 0)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  wk_start timestamptz;
  wk text;
  today_local date;
  ota jsonb;
  wallet_total int;
  -- weekly progress
  w_login int;
  w_newchat int;
  w_msg int;
  -- weekly claimed flags
  c_login boolean;
  c_social boolean;
  c_active boolean;
  daily jsonb;
  weekly jsonb;
  one_time jsonb;
begin
  select points, room_reads_today, new_chats_today, one_time_actions,
         last_login_date, login_streak
    into p
    from profiles where id = auth.uid();

  ota := coalesce(p.one_time_actions, '{}'::jsonb);
  wk_start := public.week_start_utc(tz_offset_minutes);
  wk := public.week_label(tz_offset_minutes);
  today_local := (now() + make_interval(mins => tz_offset_minutes))::date;

  -- Saldo dari ledger (source of truth) — sama seperti get_wallet
  select coalesce(sum(amount), 0) into wallet_total
    from coin_ledger where user_id = auth.uid();

  -- ── Harian ──
  daily := jsonb_build_array(
    jsonb_build_object('key','daily_login','current',
      case when p.last_login_date = today_local then 1 else 0 end,
      'target',1,'reward',public.streak_bonus_amount(greatest(coalesce(p.login_streak,1),1)),
      'done', p.last_login_date = today_local, 'claimable', false),
    jsonb_build_object('key','room_read','current',coalesce(p.room_reads_today,0),
      'target',5,'reward',2,'done',coalesce(p.room_reads_today,0) >= 5,'claimable',false),
    jsonb_build_object('key','new_chat','current',coalesce(p.new_chats_today,0),
      'target',3,'reward',5,'done',coalesce(p.new_chats_today,0) >= 3,'claimable',false),
    jsonb_build_object('key','online_5min','current',
      case when ota->>'online_5min' = 'true' then 1 else 0 end,
      'target',1,'reward',5,'done',ota->>'online_5min' = 'true','claimable',false),
    jsonb_build_object('key','online_30min','current',
      case when ota->>'online_30min' = 'true' then 1 else 0 end,
      'target',1,'reward',10,'done',ota->>'online_30min' = 'true','claimable',false),
    jsonb_build_object('key','online_60min','current',
      case when ota->>'online_60min' = 'true' then 1 else 0 end,
      'target',1,'reward',15,'done',ota->>'online_60min' = 'true','claimable',false),
    jsonb_build_object('key','online_120min','current',
      case when ota->>'online_120min' = 'true' then 1 else 0 end,
      'target',1,'reward',15,'done',ota->>'online_120min' = 'true','claimable',false)
  );

  -- ── Mingguan: progress dari point_events minggu ini ──
  select count(distinct (created_at + make_interval(mins => tz_offset_minutes))::date)
    into w_login from point_events
    where user_id = auth.uid() and event = 'daily_login' and created_at >= wk_start;
  select count(*) into w_newchat from point_events
    where user_id = auth.uid() and event = 'new_chat' and created_at >= wk_start;
  select count(*) into w_msg from point_events
    where user_id = auth.uid() and event = 'deduct' and created_at >= wk_start;

  -- Sudah diklaim minggu ini?
  select exists(select 1 from point_events where user_id = auth.uid()
    and event = 'weekly_quest' and metadata->>'key' = 'w_login' and metadata->>'week' = wk) into c_login;
  select exists(select 1 from point_events where user_id = auth.uid()
    and event = 'weekly_quest' and metadata->>'key' = 'w_social' and metadata->>'week' = wk) into c_social;
  select exists(select 1 from point_events where user_id = auth.uid()
    and event = 'weekly_quest' and metadata->>'key' = 'w_active' and metadata->>'week' = wk) into c_active;

  weekly := jsonb_build_array(
    jsonb_build_object('key','w_login','current',least(w_login,5),'target',5,'reward',50,
      'done',c_login,'claimable', w_login >= 5 and not c_login),
    jsonb_build_object('key','w_social','current',least(w_newchat,10),'target',10,'reward',50,
      'done',c_social,'claimable', w_newchat >= 10 and not c_social),
    jsonb_build_object('key','w_active','current',least(w_msg,100),'target',100,'reward',50,
      'done',c_active,'claimable', w_msg >= 100 and not c_active)
  );

  -- ── Sekali (achievement seumur hidup) ──
  one_time := jsonb_build_array(
    jsonb_build_object('key','registered','reward',100,'done',ota->>'registered' = 'true'),
    jsonb_build_object('key','rated_app','reward',20,'done',ota->>'rated_app' = 'true'),
    jsonb_build_object('key','completed_profile','reward',10,'done',ota->>'completed_profile' = 'true'),
    jsonb_build_object('key','invited_friend','reward',30,'done',ota->>'invited_friend' = 'true'),
    jsonb_build_object('key','first_photo','reward',10,'done',ota->>'first_photo' = 'true'),
    jsonb_build_object('key','first_room_chat','reward',5,'done',ota->>'first_room_chat' = 'true')
  );

  return jsonb_build_object(
    'points', wallet_total,
    'streak', coalesce(p.login_streak, 0),
    'daily', daily,
    'weekly', weekly,
    'oneTime', one_time
  );
end;
$$;