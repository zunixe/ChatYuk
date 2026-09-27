-- ============================================================
-- ChatYuk "YukCoin" v2 — SATU jalur potong untuk semua fitur berbayar
--
-- Tujuan: unifikasi sistem poin/koin lama (dual pricing 3× untuk bonus,
-- bucket 'topup' yang sudah mati) menjadi SATU konsep "YukCoin" di UI,
-- dengan SATU RPC potong: spend_yukcoin (earned dulu → bonus).
--
-- Prinsip (Jalur Lokal-first, additive-only):
--   * HANYA menambah fungsi/tabel/kolom BARU. Tidak meng-create-or-replace
--     fungsi yang dipakai prod (unlock_photo, send_coins, create_private_room,
--     send_gift, dll.) — unifikasi fitur prod ditunda ke fase promosi.
--   * Fitur v2 default OFF via app_settings.yukcoin_v2_enabled.
--   * Di lokal, flag boleh dinyalakan bebas (DB terpisah dari prod).
--
-- Model saldo (tetap 2 bucket internal, 1 angka di UI):
--   bonus  = hadiah sistem (login/misi/referral) → boleh dipakai semua fitur v2
--   earned = hasil terima gift/transfer ber-lineage uang
--   Urutan potong: earned dulu, lalu bonus (bonus = "bahan bakar", earned = "uang").
--
-- Idempotent: aman dijalankan ulang.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. Kolom konfigurasi (default = perilaku lama / OFF)
-- ──────────────────────────────────────────────
alter table public.app_settings
  add column if not exists yukcoin_v2_enabled     boolean not null default false,
  add column if not exists cost_undo_message      int not null default 10,
  add column if not exists cost_edit_message      int not null default 15,
  add column if not exists cost_extra_photo_slot  int not null default 60,
  add column if not exists cost_ghost_mode_daily  int not null default 50;

-- ──────────────────────────────────────────────
-- 2. Tabel pendukung fitur v2
-- ──────────────────────────────────────────────

-- Log pemakaian fitur YukCoin v2 (audit + idempotensi fitur tertentu).
create table if not exists public.yukcoin_consumptions (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  feature    text not null,          -- 'edit_message' | 'undo_message' | ...
  cost       int  not null,
  ref_id     text,                   -- message_id / photo_id / dll.
  metadata   jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists idx_yukcoin_consumptions_user
  on public.yukcoin_consumptions(user_id, created_at desc);

alter table public.yukcoin_consumptions enable row level security;
drop policy if exists yukcoin_consumptions_select_own on public.yukcoin_consumptions; -- SAFE: tabel baru (idempotent re-apply)
create policy yukcoin_consumptions_select_own on public.yukcoin_consumptions -- SAFE: tabel baru v2; baca hanya baris sendiri
  for select using (
    auth.uid() = user_id
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );
revoke insert, update, delete on public.yukcoin_consumptions from anon, authenticated; -- SAFE: tulis hanya via RPC (security definer)
grant select on public.yukcoin_consumptions to authenticated; -- SAFE: baca riwayat konsumsi sendiri (RLS owner)

-- Ghost mode aktif (invisible). Satu baris per user, expires_at menentukan.
create table if not exists public.ghost_mode_active (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.ghost_mode_active enable row level security;
drop policy if exists ghost_mode_select_own on public.ghost_mode_active; -- SAFE: tabel baru (idempotent re-apply)
create policy ghost_mode_select_own on public.ghost_mode_active -- SAFE: tabel baru v2; baca hanya baris sendiri
  for select using (
    auth.uid() = user_id
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );
revoke insert, update, delete on public.ghost_mode_active from anon, authenticated; -- SAFE: tulis hanya via RPC
grant select on public.ghost_mode_active to authenticated; -- SAFE: baca status diri sendiri

-- Slot foto tambahan yang sudah dibeli (sekali beli).
create table if not exists public.photo_slots_unlocked (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  extra      int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.photo_slots_unlocked enable row level security;
drop policy if exists photo_slots_unlocked_select_own on public.photo_slots_unlocked; -- SAFE: tabel baru (idempotent re-apply)
create policy photo_slots_unlocked_select_own on public.photo_slots_unlocked -- SAFE: tabel baru v2; baca hanya baris sendiri
  for select using (
    auth.uid() = user_id
    or (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
  );
revoke insert, update, delete on public.photo_slots_unlocked from anon, authenticated; -- SAFE: tulis hanya via RPC
grant select on public.photo_slots_unlocked to authenticated; -- SAFE: baca slot diri sendiri

-- ──────────────────────────────────────────────
-- 3. Helper: apakah fitur YukCoin v2 aktif untuk user ini?
--    Aktif bila flag global ON, ATAU admin (untuk test/dev).
-- ──────────────────────────────────────────────
create or replace function public.yukcoin_v2_enabled_for(p_uid uuid default auth.uid())
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v boolean;
begin
  select yukcoin_v2_enabled into v from app_settings where id = 'global';
  if v is true then return true; end if;
  -- Admin selalu boleh (test/dev).
  if coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com' then
    return true;
  end if;
  return false;
end; $$;
revoke execute on function public.yukcoin_v2_enabled_for(uuid) from public, anon;
grant execute on function public.yukcoin_v2_enabled_for(uuid) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 4. RPC inti: spend_yukcoin — SATU jalur potong (earned → bonus)
--    Return jsonb {tier, remaining, spent_bucket}
--    raise 'YukCoin tidak cukup' bila total < amount.
-- ──────────────────────────────────────────────

-- Helper: total YukCoin dihitung LANGSUNG dari ledger (tidak bergantung
-- pada baris profiles ada/tidak). Menghindari null bila profil belum dibuat.
create or replace function public.yukcoin_total(p_user uuid)
returns int
language sql
security definer
set search_path = public
as $$
  select coalesce(sum(amount), 0)::int from public.coin_ledger where user_id = p_user;
$$;
revoke execute on function public.yukcoin_total(uuid) from public, anon;
grant execute on function public.yukcoin_total(uuid) to authenticated, service_role;

create or replace function public.spend_yukcoin(
  p_user uuid,
  p_feature text,
  p_amount int,
  p_ref text default null,
  p_meta jsonb default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e int; b int; need int; take int; tier text;
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object(
      'tier', 'noop',
      'remaining', public.yukcoin_total(p_user)
    );
  end if;

  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = p_user;

  if (e + b) < p_amount then
    raise exception 'YukCoin tidak cukup';
  end if;

  need := p_amount;

  -- earned dulu
  take := least(e, need);
  if take > 0 then
    insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
      values (p_user, 'earned', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
    need := need - take;
  end if;

  -- sisanya dari bonus
  if need > 0 then
    take := least(b, need);
    if take > 0 then
      insert into public.coin_ledger(user_id, bucket, type, amount, ref_id, metadata)
        values (p_user, 'bonus', p_feature, -take, p_ref, coalesce(p_meta, '{}'::jsonb));
      need := need - take;
    end if;
  end if;

  tier := case when e >= p_amount then 'earned' else 'mixed' end;

  -- Log pemakaian + event analytics.
  insert into public.yukcoin_consumptions(user_id, feature, cost, ref_id, metadata)
    values (p_user, p_feature, p_amount, p_ref, coalesce(p_meta, '{}'::jsonb));
  insert into public.point_events(user_id, event, amount, metadata)
    values (p_user, p_feature, -p_amount,
            jsonb_build_object('feature', p_feature, 'ref', p_ref, 'tier', tier));

  return jsonb_build_object(
    'tier', tier,
    'remaining', public.yukcoin_total(p_user)
  );
end; $$;
revoke execute on function public.spend_yukcoin(uuid, text, int, text, jsonb) from public, anon;
grant execute on function public.spend_yukcoin(uuid, text, int, text, jsonb) to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 5. RPC: get_yukcoin — satu angka total untuk UI
-- ──────────────────────────────────────────────
create or replace function public.get_yukcoin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  e int; b int;
begin
  if me is null then
    return jsonb_build_object('total', 0, 'bonus', 0, 'earned', 0);
  end if;
  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b
    from public.coin_ledger
   where user_id = me;
  return jsonb_build_object('total', (e + b), 'bonus', b, 'earned', e);
end; $$;
revoke execute on function public.get_yukcoin() from public, anon;
grant execute on function public.get_yukcoin() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 6. Fitur v2 (semua lewat spend_yukcoin; gate admin/flag)
-- ──────────────────────────────────────────────

-- 6a. Undo kirim pesan (10 YukCoin). Hapus pesan milik sendiri (soft delete).
--     Mengembalikan sebagian yang dibayar saat kirim? TIDAK — biaya undo terpisah.
create or replace function public.undo_message_v2(p_message_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  cost int; owner uuid; r jsonb; has_is_deleted boolean;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;

  select cost_undo_message into cost from app_settings where id = 'global';
  select sender_id into owner from public.private_messages where id = p_message_id;
  if owner is null then raise exception 'Message not found'; end if;
  if owner <> me then raise exception 'Bukan pesanmu'; end if;

  -- Cek kolom is_deleted (ditambahkan 20260923).
  select exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='private_messages'
       and column_name='is_deleted'
  ) into has_is_deleted;

  r := public.spend_yukcoin(me, 'undo_message', cost, p_message_id::text);

  if has_is_deleted then
    update public.private_messages
       set is_deleted = true, text = ''
     where id = p_message_id and sender_id = me;
  else
    delete from public.private_messages where id = p_message_id and sender_id = me;
  end if;

  return jsonb_build_object('ok', true, 'cost', cost,
    'remaining', (r->>'remaining')::int);
end; $$;
revoke execute on function public.undo_message_v2(bigint) from public, anon;
grant execute on function public.undo_message_v2(bigint) to authenticated, service_role;

-- 6b. Edit pesan (15 YukCoin).
create or replace function public.edit_message_v2(p_message_id bigint, p_new_text text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid(); cost int; owner uuid; r jsonb;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;
  if p_new_text is null or length(btrim(p_new_text)) = 0 then
    raise exception 'Teks kosong';
  end if;
  if length(p_new_text) > 2000 then raise exception 'Teks terlalu panjang'; end if;

  select cost_edit_message into cost from app_settings where id = 'global';
  select sender_id into owner from public.private_messages where id = p_message_id;
  if owner is null then raise exception 'Message not found'; end if;
  if owner <> me then raise exception 'Bukan pesanmu'; end if;

  r := public.spend_yukcoin(me, 'edit_message', cost, p_message_id::text);

  update public.private_messages
     set text = p_new_text
   where id = p_message_id and sender_id = me;

  return jsonb_build_object('ok', true, 'cost', cost,
    'remaining', (r->>'remaining')::int);
end; $$;
revoke execute on function public.edit_message_v2(bigint, text) from public, anon;
grant execute on function public.edit_message_v2(bigint, text) to authenticated, service_role;

-- 6c. Extra photo slots (+5, sekali beli 60 YukCoin).
create or replace function public.buy_extra_photo_slots_v2(p_slots int default 5)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid(); cost int; r jsonb; cur int; new_extra int;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;
  if p_slots is null or p_slots < 1 or p_slots > 50 then
    raise exception 'Jumlah slot tidak valid';
  end if;

  select cost_extra_photo_slot into cost from app_settings where id = 'global';
  -- Biaya proporsional: 60 untuk 5 slot → 12/slot.
  cost := (cost * p_slots) / 5;

  r := public.spend_yukcoin(me, 'extra_photo_slots', cost, p_slots::text);

  insert into public.photo_slots_unlocked(user_id, extra, updated_at)
    values (me, p_slots, now())
  on conflict (user_id) do update
    set extra = public.photo_slots_unlocked.extra + p_slots,
        updated_at = now()
  returning extra into new_extra;

  return jsonb_build_object('ok', true, 'cost', cost, 'extra', new_extra,
    'remaining', (r->>'remaining')::int);
end; $$;
revoke execute on function public.buy_extra_photo_slots_v2(int) from public, anon;
grant execute on function public.buy_extra_photo_slots_v2(int) to authenticated, service_role;

-- 6d. Ghost mode (invisible) — 50 YukCoin/hari.
create or replace function public.buy_ghost_mode_v2(p_days int default 1)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid(); cost int; r jsonb; base timestamptz; new_exp timestamptz;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  if not public.yukcoin_v2_enabled_for(me) then
    raise exception 'Fitur belum aktif';
  end if;
  if p_days is null or p_days < 1 or p_days > 30 then
    raise exception 'Durasi tidak valid';
  end if;

  select cost_ghost_mode_daily into cost from app_settings where id = 'global';
  cost := cost * p_days;

  r := public.spend_yukcoin(me, 'ghost_mode', cost, p_days::text);

  -- Perpanjang dari expires_at yang masih berlaku, atau dari now().
  select expires_at into base from public.ghost_mode_active where user_id = me;
  if base is null or base < now() then base := now(); end if;
  new_exp := base + (p_days || ' days')::interval;

  insert into public.ghost_mode_active(user_id, expires_at)
    values (me, new_exp)
  on conflict (user_id) do update set expires_at = excluded.expires_at;

  return jsonb_build_object('ok', true, 'cost', cost,
    'expires_at', new_exp,
    'remaining', (r->>'remaining')::int);
end; $$;
revoke execute on function public.buy_ghost_mode_v2(int) from public, anon;
grant execute on function public.buy_ghost_mode_v2(int) to authenticated, service_role;

-- 6e. Cek status ghost mode user.
create or replace function public.is_ghost_mode()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ghost_mode_active
    where user_id = auth.uid() and expires_at > now()
  );
$$;
revoke execute on function public.is_ghost_mode() from public, anon;
grant execute on function public.is_ghost_mode() to authenticated, service_role;

-- 6f. Baca slot foto tambahan milik user (untuk limit galeri di client).
create or replace function public.my_extra_photo_slots()
returns int
language sql
security definer
set search_path = public
as $$
  select coalesce((select extra from public.photo_slots_unlocked
                    where user_id = auth.uid()), 0);
$$;
revoke execute on function public.my_extra_photo_slots() from public, anon;
grant execute on function public.my_extra_photo_slots() to authenticated, service_role;

-- 6g. Status ringkas YukCoin v2 untuk UI: {active, total, ghost, extra_slots}.
create or replace function public.yukcoin_v2_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  e int; b int; g boolean; ex int;
begin
  if me is null then
    return jsonb_build_object('active', false, 'total', 0,
      'ghost', false, 'extra_slots', 0);
  end if;
  select coalesce(sum(amount) filter (where bucket = 'earned'), 0),
         coalesce(sum(amount) filter (where bucket = 'bonus'), 0)
    into e, b from public.coin_ledger where user_id = me;
  select exists (select 1 from public.ghost_mode_active
                  where user_id = me and expires_at > now()) into g;
  select coalesce((select extra from public.photo_slots_unlocked
                    where user_id = me), 0) into ex;
  return jsonb_build_object(
    'active', public.yukcoin_v2_enabled_for(me),
    'total', (e + b),
    'bonus', b,
    'earned', e,
    'ghost', coalesce(g, false),
    'extra_slots', coalesce(ex, 0)
  );
end; $$;
revoke execute on function public.yukcoin_v2_status() from public, anon;
grant execute on function public.yukcoin_v2_status() to authenticated, service_role;

-- ──────────────────────────────────────────────
-- 7. Isi ulang cache profiles.points dari ledger (jaga konsistensi)
-- ──────────────────────────────────────────────
update public.profiles pr
   set points = w.total_balance
  from public.wallet_balances w
 where w.user_id = pr.id;
