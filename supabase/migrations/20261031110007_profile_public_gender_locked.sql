-- Tambah `gender_locked` ke payload `profile_public` agar UI bisa menampilkan
-- status kunci gender (read-only) di edit profil. Tanpa ini, `genderLocked`
-- selalu false → dropdown gender tetap bisa diubah (walau server menolak).

CREATE OR REPLACE FUNCTION public.profile_public(p_user uuid DEFAULT auth.uid())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.profiles%rowtype;
  me uuid := auth.uid();
  v_is_me boolean := (p_user = auth.uid());
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;

  return jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'gender_locked', coalesce(r.gender_locked, false),
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case when public.privacy_can_view(r.id, 'presence', me)
                   then r.status else 'offline' end,
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
    'phone_verified_at',
      case when v_is_me then r.phone_verified_at else null end,
    -- Kapan negara boleh diubah lagi (khusus diri sendiri).
    'country_changed_at',
      case when v_is_me then r.country_changed_at else null end
  );
end;
$function$;

REVOKE EXECUTE ON FUNCTION public.profile_public(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profile_public(uuid) TO authenticated, service_role;
