-- P0: index kritis + incremental balance (hapus sum(coin_ledger) per spend)

-- Index hilang
create index if not exists idx_room_presence_joined_at on public.room_presence(joined_at);
create index if not exists idx_blocks_reverse on public.blocks(blocked_id, blocker_id);
create index if not exists idx_follows_follower on public.follows(follower_id, created_at);
create index if not exists idx_posts_author_boost_created on public.posts(author_id, is_boosted desc, created_at desc);
create index if not exists idx_private_messages_sender on public.private_messages(sender_id, created_at);
create index if not exists idx_coin_ledger_user_bucket_created on public.coin_ledger(user_id, bucket, created_at);

-- Incremental balance: tambah kolom
alter table public.profiles add column if not exists bonus_balance int not null default 0;
alter table public.profiles add column if not exists topup_balance int not null default 0;
alter table public.profiles add column if not exists earned_balance int not null default 0;

-- Backfill sekali (ambil dari coin_ledger)
update public.profiles p set
  bonus_balance = coalesce((select sum(amount) from public.coin_ledger where user_id=p.id and bucket='bonus'),0),
  topup_balance = coalesce((select sum(amount) from public.coin_ledger where user_id=p.id and bucket='topup'),0),
  earned_balance = coalesce((select sum(amount) from public.coin_ledger where user_id=p.id and bucket='earned'),0)
where exists (select 1 from public.coin_ledger where user_id=p.id);

-- Trigger incremental
create or replace function public.trg_coin_ledger_balance() returns trigger language plpgsql as $$
begin
  update public.profiles set
    bonus_balance = bonus_balance + case when new.bucket='bonus' then new.amount else 0 end,
    topup_balance = topup_balance + case when new.bucket='topup' then new.amount else 0 end,
    earned_balance = earned_balance + case when new.bucket='earned' then new.amount else 0 end,
    points = points + new.amount
  where id=new.user_id;
  return new;
end; $$;

drop trigger if exists coin_ledger_balance_trg on public.coin_ledger;
create trigger coin_ledger_balance_trg after insert on public.coin_ledger for each row execute function public.trg_coin_ledger_balance();

-- wallet_sync_points jadi baca kolom (tidak sum lagi)
create or replace function public.wallet_sync_points(p_user uuid) returns int language sql security definer set search_path=public as $$
  select points from public.profiles where id=p_user;
$$;
