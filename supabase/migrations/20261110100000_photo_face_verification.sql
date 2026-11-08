-- Verifikasi wajah foto profil (khusus akun FEMALE).
--
-- Foto profil female wajib berasal dari selfie liveness (kamera in-app:
-- kedip + toleh). Setelah lolos, klien mencatat cap waktu di kolom baru.
-- Foto lama (tanpa cap) tetap tampil tetapi UI menandai "perlu diganti".
--
-- SAFE: menambah kolom NULLABLE baru saja — tidak ada DROP TABLE/COLUMN,
-- tidak mengubah tipe kolom lama, dan semua fitur lama tetap jalan karena
-- kolom opsional (null = belum/tidak diverifikasi). Klien versi lama yang
-- tidak mengenal kolom ini tidak terpengaruh (insert/update parsial).

alter table public.profiles
  add column if not exists avatar_face_verified_at timestamptz;

alter table public.user_photos
  add column if not exists face_verified_at timestamptz;

-- Foto sendiri: sertakan status verifikasi supaya grid Profil bisa
-- menandai foto lama yang perlu diganti.
create or replace function public.my_photos()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  arr jsonb;
begin
  if me is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',         r.id,
    'unlocked',   true,
    'photo',      r.photo,
    'preview',    coalesce(r.photo_preview, ''),
    'created_at', r.created_at,
    'face_verified', r.face_verified_at is not null
  ) order by r.created_at asc), '[]'::jsonb) into arr
  from public.user_photos r where r.user_id = me;
  return arr;
end;
$function$;

-- Status avatar terverifikasi HANYA dikirim untuk diri sendiri (data
-- verifikasi bukan informasi publik).
create or replace function public.profile_public(p_user uuid default auth.uid())
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
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
      case when v_is_me then r.country_changed_at else null end,
    -- Avatar sudah lolos selfie liveness? (khusus diri sendiri)
    'avatar_face_verified',
      case when v_is_me then (r.avatar_face_verified_at is not null) else null end
  );
end;
$function$;
