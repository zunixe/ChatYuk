-- ============================================================
-- profile_public: sertakan phone / birth_date / phone_verified_at
-- HANYA untuk DIRI SENDIRI (r.id = auth.uid()).
--
-- LATAR (bug 2026-10-09): user menyelesaikan verifikasi nomor via Telegram
-- (server menandai profiles.phone + phone_verified_at), tapi di app nomor HP
-- tetap tampil "Belum diisi" dan badge tak muncul. Akar: RPC `profile_public`
-- yang dipakai `getProfile()` TIDAK mengembalikan kolom `phone` sama sekali →
-- `UserModel.phone` selalu '' walau data ada di server.
--
-- `birth_date` juga tak dikembalikan (padahal UserModel membacanya).
--
-- PRIVASI: nomor HP & tanggal lahir adalah data SENSITIF. Hanya dikembalikan
-- bila p_user = auth.uid() (diri sendiri) — user lain TIDAK pernah menerima
-- field ini (tak berubah dari sebelumnya: sebelumnya juga tak pernah dikirim).
-- `phone_verified_at` → dipakai badge diri sendiri.
--
-- Idempotent (create or replace). Tidak menyentuh fungsi FROZEN.
-- CARA APPLY: Management API POST /v1/projects/{ref}/database/query.
-- ============================================================

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
  v_is_me boolean := (p_user = me);
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
    'friends_count', r.friends_count,
    -- Hanya untuk diri sendiri (data sensitif).
    'phone', case when v_is_me then coalesce(r.phone, '') else '' end,
    'birth_date', case when v_is_me then r.birth_date else null end,
    'phone_verified_at', case when v_is_me then r.phone_verified_at else null end
  );
end;
$function$;
