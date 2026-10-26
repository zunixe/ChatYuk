-- ============================================================
-- LENGKAPI penegakan GHOST MODE — tutup 2 jalur bocor yang tersisa.
--
-- Migrasi 20261027121000 sudah menutup `get_online_users` dan `presence_for`.
-- Audit ulang (2026-10-26) menemukan DUA jalur lain yang masih membocorkan
-- status asli user ghost:
--
--   1) `profile_public(p_user)` — mengembalikan `status` mentah
--      (`case when privacy_can_view(...) then r.status else 'offline' end`).
--      Dipakai halaman profil → badge Online tetap menyala untuk user ghost.
--
--   2) REALTIME `postgres_changes` pada tabel `profiles`
--      (channel `user-status-<uid>` di chat_service_presence.dart). Callback
--      klien membaca `payload.newRecord['status']` MENTAH. Jadi saat user
--      ghost berganti status, perubahan itu terkirim ke penonton apa adanya —
--      ghost hanya tersembunyi saat fetch awal, lalu bocor lewat realtime.
--
-- PERBAIKAN:
--   (1) `profile_public`: status ghost dipaksa 'offline' bagi selain pemilik.
--   (2) Trigger `enforce_ghost_mode_status`: selama ghost aktif, `profiles.status`
--       DIPAKSA 'offline' — supaya realtime pun mengirim 'offline'.
--
-- KENAPA (2) AMAN & LEBIH BAIK dari menambal klien:
--   Ghost Mode menjanjikan "sembunyikan status online" — jadi status yang
--   tersimpan pun memang seharusnya 'offline'. Heartbeat klien tetap memperbarui
--   `last_seen` (fitur last_seen_visibility tak terpengaruh), dan saat ghost
--   kedaluwarsa trigger berhenti memaksa → heartbeat berikutnya mengembalikan
--   'online' otomatis. Tidak perlu ubah klien sama sekali.
--
-- TIDAK mengubah privacy_can_view, ghost milik admin
-- (`app_settings.invisible_admin_uid`), atau semantik tabel apa pun.
--
-- CARA APPLY: Management API / SQL editor (CLI db push HANG di Mac ini).
-- ROLLBACK: re-apply `20261009200000_profile_public_self_phone.sql` dan
--           `drop trigger if exists trg_enforce_ghost_mode on public.profiles;`
-- ============================================================

-- ── 1) profile_public: paksa 'offline' untuk user ghost ────────────────────
create or replace function public.profile_public(p_user uuid default auth.uid())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  r public.profiles%rowtype;
  me uuid := auth.uid();
  v_is_me boolean := (p_user = auth.uid());
  v_ghost boolean;
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;

  -- Ghost mode membeli privasi PRESENCE. Pemilik tetap melihat status aslinya.
  v_ghost := (not v_is_me) and exists (
    select 1 from public.ghost_mode_active g
    where g.user_id = r.id and g.expires_at > now()
  );

  return jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case
                when v_ghost then 'offline'
                when public.privacy_can_view(r.id, 'presence', me) then r.status
                else 'offline' end,
    'avatar', case when public.privacy_can_view(r.id, 'profile_photo', me) then r.avatar else '' end,
    'is_registered', r.is_registered,
    'needs_onboarding', coalesce(r.needs_onboarding, false),
    'login_at', r.login_at,
    'created_at', r.created_at,
    'last_seen', case when public.privacy_can_view(r.id, 'last_seen', me) then r.last_seen else null end,
    'about', case when public.privacy_can_view(r.id, 'about', me) then r.about else '' end,
    'hashtags', r.hashtags,
    'points', case when r.id = me then r.points else 0 end,
    'share_location', case when r.id = me then r.share_location else false end,
    'followers_count', r.followers_count,
    'following_count', r.following_count,
    'subscriber_count', r.subscriber_count,
    'subscription_price', r.subscription_price,
    'friends_count', r.friends_count,
    'phone', case when v_is_me then coalesce(r.phone, '') else '' end,
    'birth_date', case when v_is_me then r.birth_date else null end,
    'phone_verified_at', case when v_is_me then r.phone_verified_at else null end
  );
end;
$function$;

-- ── 2) Trigger: paksa status 'offline' selama ghost aktif ──────────────────
create or replace function public.enforce_ghost_mode_status()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- Jangan sentuh saat status sengaja 'invisible' (ghost milik admin) —
  -- mekanisme itu punya enforcement sendiri (trg_enforce_invisible).
  if new.status in ('online', 'idle') and exists (
    select 1 from public.ghost_mode_active g
    where g.user_id = new.id and g.expires_at > now()
  ) then
    new.status := 'offline';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_ghost_mode on public.profiles;
create trigger trg_enforce_ghost_mode
  before insert or update on public.profiles
  for each row execute function public.enforce_ghost_mode_status();

-- ── 3) Rapikan baris yang sedang ghost tapi statusnya masih online ─────────
update public.profiles p
   set status = 'offline'
 where p.status in ('online', 'idle')
   and exists (
     select 1 from public.ghost_mode_active g
     where g.user_id = p.id and g.expires_at > now()
   );
