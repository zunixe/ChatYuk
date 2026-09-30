-- ============================================================
-- needs_onboarding: cegah "user hantu" TANPA efek "login anon otomatis".
--
-- KONTEKS (2026-10-04):
--   Trigger `handle_new_user_profile` sempat dipasang untuk mencegah user
--   hantu (auth.users tanpa profiles). Tapi karena trigger membuat profil
--   untuk SEMUA user anon, gate `decideGateScreen`
--   (`!hasProfile && isAnonymous -> entry`) jadi false → user anon
--   LANGSUNG masuk app tanpa layar isi nickname ("login anon otomatis").
--   Trigger di-rollback (20261004040000).
--
-- SOLUSI (Opsi B): tandai profil hasil trigger dengan `needs_onboarding`.
--   - Kolom baru `needs_onboarding boolean not null default true`.
--   - Trigger membuat profil dengan `needs_onboarding = true`.
--   - Gate: user anon dengan `needs_onboarding=true` → EntryScreen
--     (minta isi nickname); user email dengan true → profileGate.
--   - `registerProfile` mengeset `needs_onboarding = false` setelah user
--     menyelesaikan isi nickname.
--
-- BACKFILL: SELURUH profil LAMA diset `false` (keputusan user 2026-10-04:
--   "jangan ganggu" user lama; efek hanya untuk user BARU). Termasuk 20
--   user nickname auto 'AnonXXXXXX' lama → false (dibiarkan langsung masuk).
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

-- ── 1) Kolom baru. Default TRUE = aman untuk user baru. ────────────────
alter table public.profiles
  add column if not exists needs_onboarding boolean not null default true;

-- ── 2) Backfill: SEMUA profil lama → false (tidak ada yang diganggu). ──
update public.profiles set needs_onboarding = false where needs_onboarding is true;

-- ── 3) Expose di profile_public (agar UserModel bisa membacanya). ─────
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
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;
  return jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case when public.privacy_can_view(r.id, 'presence', me) then r.status else 'offline' end,
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
    'friends_count', r.friends_count
  );
end;
$function$;

-- Verifikasi setelah apply:
--   select count(*) filter (where needs_onboarding) as perlu_onboarding,
--          count(*) as total from profiles;      -- perlu_onboarding = 0
--   select position('needs_onboarding' in
--     pg_get_functiondef('public.profile_public(uuid)'::regprocedure)) > 0;
--                                                -- true
