-- menyentuh: my_photos, get_user_photos_access
-- Video di "Foto Saya" (galeri profil): foto DAN video dalam slot yang sama.
--
-- Desain: TIDAK ada kolom baru. `user_photos.photo` sudah menyimpan PATH
-- storage; video memakai path berakhiran `.mp4` di folder `gallery/` yang
-- sama, poster thumbnail disimpan di file pasangan `<nama>_poster.jpg`
-- (dibaca klien dari path video — bukan kolom DB).
--
-- Kenapa RPC perlu diubah: untuk foto TERKUNCI (paywall) server mengirim
-- `photo` = preview blur (base64), sehingga klien tidak bisa tahu item itu
-- video atau foto dari nilainya. `is_video` dihitung dari path ASLI
-- (`rec.photo`), jadi tetap benar walau `photo` yang dikirim adalah preview.
--
-- SAFE: hanya menambah key JSON pada output dua RPC; tidak ada perubahan
-- skema/tipe kolom, klien lama mengabaikan key baru.
--
-- Basis versi: supabase/snapshots/functions_all.sql (live), bukan salinan
-- migrasi lama — cabang paywall (unlock_photo/photo_unlocks) tetap utuh.

-- ── 1. my_photos: tandai video (milik sendiri) ──
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
    'face_verified', r.face_verified_at is not null,
    -- Video galeri (mp4/mov/webm) — dihitung dari path ASLI.
    'is_video',   r.photo ~* '\.(mp4|mov|webm)$'
  ) order by r.created_at asc), '[]'::jsonb) into arr
  from public.user_photos r where r.user_id = me;
  return arr;
end;
$function$;

-- ── 2. get_user_photos_access: tandai video (profil orang lain) ──
create or replace function public.get_user_photos_access(p_user_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  points_on boolean;
  owner_female boolean;
  arr jsonb := '[]'::jsonb;
  rec record;
  idx int := 0;
  is_unlocked boolean;
begin
  select points_enabled into points_on from app_settings where id = 'global';
  select gender = 'female' into owner_female
    from profiles where id = p_user_id;

  for rec in
    select id, photo, photo_preview, created_at
    from user_photos where user_id = p_user_id
    order by created_at asc
  loop
    -- Terbuka: koin mati / foto sendiri / profil non-female (paywall hanya
    -- untuk foto milik female) / 4 pertama / sudah beli permanen.
    is_unlocked := (points_on is false)
                or (me = p_user_id)
                or (owner_female is not true)
                or (idx < 4)
                or exists (select 1 from photo_unlocks
                           where viewer_id = me and photo_id = rec.id);

    arr := arr || jsonb_build_object(
      'id', rec.id,
      'unlocked', is_unlocked,
      -- Foto asli hanya dikirim bila terbuka; jika terkunci kirim preview blur.
      'photo', case when is_unlocked then rec.photo else coalesce(rec.photo_preview, '') end,
      'preview', coalesce(rec.photo_preview, ''),
      'created_at', rec.created_at,
      -- Video galeri: dihitung dari path ASLI supaya item TERKUNCI tetap
      -- bisa menampilkan badge video (photo yang dikirim = preview blur).
      'is_video', rec.photo ~* '\.(mp4|mov|webm)$'
    );
    idx := idx + 1;
  end loop;

  return arr;
end; $function$;
