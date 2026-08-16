-- ============================================================
-- ChatYuk: Referral share tracking (per-klik + anti-farming)
--
-- - app_settings: share_url (tujuan redirect, admin bisa ganti),
--   share_click_reward (koin per klik valid), share_click_cap_daily
--   (maksimal klik berreward per hari per pengirim).
-- - referral_clicks: catat tiap klik unik (sharer + ip + hari) untuk
--   dedup & anti-farming. Reward hanya untuk IP berbeda dari sharer &
--   belum pernah dihitung di hari yang sama.
-- - RPC award_share_click(sharer, ip): dipanggil edge function 'r'.
--   Future-proof untuk per-install (Play Install Referrer) nanti.
-- ============================================================

alter table public.app_settings
  add column if not exists share_url text not null default 'https://apkpure.com/chatyuk/com.chatyuk.chatyuk',
  add column if not exists share_click_reward int not null default 5,
  add column if not exists share_click_cap_daily int not null default 20;

create table if not exists public.referral_clicks (
  id          bigint generated always as identity primary key,
  sharer_id   uuid not null references auth.users(id) on delete cascade,
  click_ip    text,
  click_day   date not null default (now() at time zone 'Asia/Jakarta')::date,
  rewarded    boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists idx_referral_clicks_sharer_day
  on public.referral_clicks(sharer_id, click_day);
-- Dedup: satu IP hanya dihitung sekali per sharer per hari.
create unique index if not exists uq_referral_click_dedup
  on public.referral_clicks(sharer_id, click_ip, click_day);

alter table public.referral_clicks enable row level security;
-- Hanya pemilik yang boleh lihat statistik kliknya sendiri.
drop policy if exists referral_clicks_select_own on public.referral_clicks;
create policy referral_clicks_select_own on public.referral_clicks
  for select using (sharer_id = auth.uid());

-- ============================================================
-- RPC: award_share_click — dipanggil edge function (service role).
-- Return jsonb {rewarded: bool, reason: text}. Anti-farming:
--   - IP klik tidak boleh sama dengan IP sharer terakhir (self-click)
--   - dedup unik (sharer, ip, hari)
--   - cap harian share_click_cap_daily
--   - hanya jalan bila points_enabled
-- ============================================================
create or replace function public.award_share_click(p_sharer uuid, p_ip text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  points_on boolean;
  reward int;
  cap int;
  sharer_ip text;
  today date := (now() at time zone 'Asia/Jakarta')::date;
  rewarded_today int;
  do_reward boolean := false;
begin
  if p_sharer is null then
    return jsonb_build_object('rewarded', false, 'reason', 'no_sharer');
  end if;
  if not exists (select 1 from profiles where id = p_sharer) then
    return jsonb_build_object('rewarded', false, 'reason', 'invalid_sharer');
  end if;

  select points_enabled, share_click_reward, share_click_cap_daily
    into points_on, reward, cap from app_settings where id = 'global';

  -- Catat klik (dedup unik per sharer+ip+hari). Kalau duplikat → tidak reward.
  begin
    -- Self-click: IP sama dengan IP terakhir sharer → catat tanpa reward.
    select ip_address into sharer_ip from profiles where id = p_sharer;

    select count(*) into rewarded_today
      from referral_clicks
      where sharer_id = p_sharer and click_day = today and rewarded = true;

    do_reward := points_on is true
             and p_ip is not null
             and (sharer_ip is null or p_ip <> sharer_ip)
             and rewarded_today < cap;

    insert into referral_clicks (sharer_id, click_ip, click_day, rewarded)
      values (p_sharer, p_ip, today, do_reward);
  exception when unique_violation then
    -- IP ini sudah dihitung hari ini untuk sharer ini → tidak reward.
    return jsonb_build_object('rewarded', false, 'reason', 'duplicate');
  end;

  if do_reward then
    perform public.ledger_credit(p_sharer, 'bonus', 'share_click', reward,
              null, jsonb_build_object('ip', p_ip));
    insert into point_events (user_id, event, amount, metadata)
      values (p_sharer, 'share_click', reward, jsonb_build_object('ip', p_ip));
    return jsonb_build_object('rewarded', true, 'reward', reward);
  end if;

  return jsonb_build_object('rewarded', false, 'reason',
    case when points_on is not true then 'points_off'
         when rewarded_today >= cap then 'cap_reached'
         else 'no_reward' end);
end;
$$;
revoke execute on function public.award_share_click(uuid, text) from public, anon;
grant execute on function public.award_share_click(uuid, text) to service_role;

-- ============================================================
-- RPC: statistik share milik sendiri (untuk UI).
-- ============================================================
create or replace function public.my_share_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not authenticated'; end if;
  return jsonb_build_object(
    'total_clicks', (select count(*) from referral_clicks where sharer_id = me),
    'rewarded_clicks', (select count(*) from referral_clicks where sharer_id = me and rewarded = true),
    'today_rewarded', (select count(*) from referral_clicks
                       where sharer_id = me and rewarded = true
                       and click_day = (now() at time zone 'Asia/Jakarta')::date)
  );
end;
$$;
revoke execute on function public.my_share_stats() from public, anon;
grant execute on function public.my_share_stats() to authenticated;

-- ============================================================
-- Tambah share_url & reward ke admin get/update point settings.
-- ============================================================
create or replace function public.admin_get_point_settings()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  return (select jsonb_build_object(
    'photo_upload_reward', photo_upload_reward,
    'photo_unlock_once', photo_unlock_once,
    'photo_unlock_perm', photo_unlock_perm,
    'photo_unlock_owner_pct', photo_unlock_owner_pct,
    'bonus_registered', bonus_registered,
    'bonus_rated', bonus_rated,
    'bonus_shared', bonus_shared,
    'bonus_profile', bonus_profile,
    'bonus_first_photo', bonus_first_photo,
    'bonus_room_read', bonus_room_read,
    'bonus_new_chat', bonus_new_chat,
    'cost_chat_text', cost_chat_text,
    'cost_chat_image', cost_chat_image,
    'cost_view_once', cost_view_once,
    'share_url', share_url,
    'share_click_reward', share_click_reward,
    'share_click_cap_daily', share_click_cap_daily
  ) from app_settings where id = 'global');
end; $$;
revoke execute on function public.admin_get_point_settings() from public, anon;
grant execute on function public.admin_get_point_settings() to authenticated, service_role;

create or replace function public.admin_update_point_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update app_settings set
    photo_upload_reward   = coalesce((p->>'photo_upload_reward')::int, photo_upload_reward),
    photo_unlock_once     = coalesce((p->>'photo_unlock_once')::int, photo_unlock_once),
    photo_unlock_perm     = coalesce((p->>'photo_unlock_perm')::int, photo_unlock_perm),
    photo_unlock_owner_pct= coalesce((p->>'photo_unlock_owner_pct')::int, photo_unlock_owner_pct),
    bonus_registered      = coalesce((p->>'bonus_registered')::int, bonus_registered),
    bonus_rated           = coalesce((p->>'bonus_rated')::int, bonus_rated),
    bonus_shared          = coalesce((p->>'bonus_shared')::int, bonus_shared),
    bonus_profile         = coalesce((p->>'bonus_profile')::int, bonus_profile),
    bonus_first_photo     = coalesce((p->>'bonus_first_photo')::int, bonus_first_photo),
    bonus_room_read       = coalesce((p->>'bonus_room_read')::int, bonus_room_read),
    bonus_new_chat        = coalesce((p->>'bonus_new_chat')::int, bonus_new_chat),
    cost_chat_text        = coalesce((p->>'cost_chat_text')::int, cost_chat_text),
    cost_chat_image       = coalesce((p->>'cost_chat_image')::int, cost_chat_image),
    cost_view_once        = coalesce((p->>'cost_view_once')::int, cost_view_once),
    share_url             = coalesce(p->>'share_url', share_url),
    share_click_reward    = coalesce((p->>'share_click_reward')::int, share_click_reward),
    share_click_cap_daily = coalesce((p->>'share_click_cap_daily')::int, share_click_cap_daily),
    updated_at = now()
  where id = 'global';
  return (select to_jsonb(a) from app_settings a where id = 'global');
end; $$;
revoke execute on function public.admin_update_point_settings(jsonb) from public, anon;
grant execute on function public.admin_update_point_settings(jsonb) to authenticated, service_role;

-- RPC publik untuk edge function ambil share_url (tanpa auth admin).
create or replace function public.get_share_url()
returns text language sql security definer set search_path = public as $$
  select coalesce(share_url, 'https://apkpure.com/chatyuk/com.chatyuk.chatyuk')
  from app_settings where id = 'global';
$$;
grant execute on function public.get_share_url() to anon, authenticated, service_role;
