-- profile_public: kirim `nickname_set` (HANYA untuk diri sendiri).
--
-- Dibutuhkan gerbang "wajib isi username": app perlu tahu apakah user
-- sudah pernah memilih username. Kolom ini data PRIBADI — hanya dikirim
-- bila viewer = pemilik profil (r.id = me), bukan ke user lain.
--
-- Kolom ditambahkan di 20261002070000_profiles_nickname_set_gate.sql.
create or replace function public.profile_public(p_user uuid default auth.uid())
returns jsonb
language plpgsql
stable security definer
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
    -- PRIBADI: hanya pemilik profil. Dipakai gerbang isi username.
    'nickname_set', case when r.id = me then r.nickname_set else null end,
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
