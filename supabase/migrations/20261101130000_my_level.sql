-- ============================================================
-- 130000 — My Level (level dari kumulatif topup, MALE only)
-- ============================================================
-- Rujukan: halaman "My Level" app referensi (capture Xiaomi).
--   • Level = kumulatif koin TOPUP (coin_ledger bucket 'topup',
--     hanya amount > 0) — welcome bonus/penghasilan TIDAK dihitung.
--   • Naik level → reward koin ke bucket 'bonus' (non-withdrawable,
--     tidak feed-forward ke level karena bucket-nya beda).
--   • Idempoten: reward per level hanya sekali (user_level_state.
--     reward_granted_level), RPC dipanggil ulang tidak dobel-credit.
--   • MALE only: female/dummy tidak pernah punya level (guard gender
--     di get_my_level & get_user_level → return level 0).
--   • Kill-switch ekonomi: points_enabled=false → reward tidak dicetak.
--
-- Tabel baru (bukan tabel bersama lintas-fitur):
--   level_config     — tangga level (admin ubah via SQL/dashboard).
--   user_level_state — penanda reward per level sudah dicetak.
--
-- Fungsi baru (BUKAN FROZEN): get_my_level(), get_user_level(p_user).
-- Tidak menyentuh credit_play_topup / charge_metered / profile_public.
--
-- CARA APPLY: Management API / SQL editor (CLI db push HANG di Mac ini).
-- ROLLBACK: drop function get_my_level/get_user_level;
--           drop table user_level_state, level_config;
-- ============================================================

-- ── 1. level_config — tangga level (skala ChatYuk) ──────────────
create table if not exists public.level_config (
  level        int primary key check (level >= 0),
  topup_coins  int not null check (topup_coins >= 0),
  reward_coins int not null default 0 check (reward_coins >= 0)
);

insert into public.level_config (level, topup_coins, reward_coins) values
  (0,  0,      0),
  (1,  700,    50),
  (2,  2000,   100),
  (3,  5000,   150),
  (4,  12000,  200),
  (5,  25000,  300),
  (6,  55000,  400),
  (7,  120000, 500),
  (8,  250000, 750),
  (9,  500000, 1000),
  (10, 1000000, 2000)
on conflict (level) do update set
  topup_coins  = excluded.topup_coins,
  reward_coins = excluded.reward_coins;

alter table public.level_config enable row level security;
create policy level_config_read on public.level_config for select to authenticated using (true);  -- SAFE: config tangga level read-only utk authenticated; INSERT/UPDATE/DELETE tanpa policy → ditolak default (admin via service_role)
grant select on public.level_config to authenticated;  -- SAFE: client butuh baca tangga utk render tabel rule; tulis tetap tertutup
revoke insert, update, delete, truncate on public.level_config from anon, authenticated;  -- SAFE: hardening standar tabel config — hanya service_role boleh menulis

-- ── 2. user_level_state — penanda reward sudah dicetak ──────────
create table if not exists public.user_level_state (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  level               int not null default 0,
  reward_granted_level int not null default 0,
  updated_at          timestamptz not null default now()
);

alter table public.user_level_state enable row level security;
create policy user_level_state_read_own on public.user_level_state for select to authenticated using (user_id = auth.uid());  -- SAFE: state level milik sendiri saja; tulis hanya via RPC security definer (tanpa policy write)
grant select on public.user_level_state to authenticated;  -- SAFE: baca baris sendiri (policy di atas); tulis tertutup
revoke insert, update, delete, truncate on public.user_level_state from anon, authenticated;  -- SAFE: hardening standar — penulisan hanya lewat RPC get_my_level (security definer)

-- ── 3. get_my_level — hitung level + grant reward idempoten ─────
create or replace function public.get_my_level()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  cum int;
  lvl int;
  st public.user_level_state;
  l record;
  ladder jsonb;
  just_rewarded jsonb := '[]'::jsonb;
  points_on boolean;
  v_gender text;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  -- Kumulatif topup = hanya kredit bucket 'topup' (amount > 0).
  -- Spend (amount negatif) & bucket lain tidak mengurangi/menaikkan.
  select coalesce(sum(amount), 0) into cum
    from coin_ledger
   where user_id = me and bucket = 'topup' and amount > 0;

  select coalesce(max(level), 0) into lvl
    from level_config where topup_coins <= cum;

  select gender into v_gender from profiles where id = me;

  select points_enabled into points_on from app_settings where id = 'global';

  -- State + grant reward (idempoten): lock baris agar panggilan paralel
  -- tidak dobel-credit (pola advisory-lock ala ledger_spend).
  select * into st from user_level_state where user_id = me for update;
  if not found then
    insert into user_level_state (user_id, level, reward_granted_level)
      values (me, lvl, 0)
      on conflict (user_id) do nothing;
    select * into st from user_level_state where user_id = me for update;
  end if;

  -- Reward hanya MALE (fitur My Level = male only) + kill-switch ekonomi.
  if lvl > st.reward_granted_level
     and v_gender = 'male'
     and points_on is not false then
    for l in select level, reward_coins from level_config
             where level > st.reward_granted_level
               and level <= lvl
               and reward_coins > 0
             order by level
    loop
      perform public.ledger_credit(me, 'bonus', 'level_reward',
        l.reward_coins, 'level_' || l.level,
        jsonb_build_object('level', l.level));
      just_rewarded := just_rewarded || jsonb_build_array(
        jsonb_build_object('level', l.level, 'coins', l.reward_coins));
    end loop;
    update user_level_state
       set reward_granted_level = lvl, level = lvl, updated_at = now()
     where user_id = me;
  else
    update user_level_state
       set level = lvl, updated_at = now()
     where user_id = me and level is distinct from lvl;
  end if;

  select jsonb_agg(jsonb_build_object(
           'level', x.level, 'topup_coins', x.topup_coins,
           'reward_coins', x.reward_coins) order by x.level)
    into ladder
    from level_config x;

  return jsonb_build_object(
    'level', lvl,
    'cumulative', cum,
    'next_level', (select min(level) from level_config where topup_coins > cum),
    'next_at',    (select min(topup_coins) from level_config where topup_coins > cum),
    'remaining',  coalesce((select min(topup_coins) from level_config where topup_coins > cum), 0) - cum,
    'ladder', coalesce(ladder, '[]'::jsonb),
    'just_rewarded', just_rewarded
  );
end;
$$;
revoke execute on function public.get_my_level() from public, anon;
grant execute on function public.get_my_level() to authenticated, service_role;

-- ── 4. get_user_level — badge level untuk user lain ─────────────
-- Level bukan data sensitif; female/dummy memang tidak pernah topup →
-- guard gender menjaga fitur tetap male-only.
create or replace function public.get_user_level(p_user uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object('level', case
    when (select gender from profiles where id = p_user) <> 'male' then 0
    else coalesce((
      select max(lc.level)
        from level_config lc
       where lc.topup_coins <= (
         select coalesce(sum(amount), 0)
           from coin_ledger
          where user_id = p_user and bucket = 'topup' and amount > 0
       )
    ), 0)
  end);
$$;
revoke execute on function public.get_user_level(uuid) from public, anon;
grant execute on function public.get_user_level(uuid) to authenticated, service_role;
