-- ============================================================
-- Trigger pembuat profil: user REGISTERED tidak lagi dapat nickname
-- placeholder 'AnonXXXXXXXX'.
--
-- LATAR (2026-10-05): trigger `handle_new_user_profile` membuat nickname
--   'Anon' + hex untuk SETIAP auth.users — termasuk user yang daftar via
--   EMAIL/GOOGLE (registered). Akibatnya user registered sempat punya
--   nickname 'AnonXXXXXX' (membingungkan; terlihat seperti akun anon),
--   dan kalau user tutup app sebelum memilih nama, nickname itu tertinggal.
--
-- PERUBAHAN: nickname placeholder dibedakan:
--   - ANON  (email kosong)   → 'Anon' + 8 hex  (tetap; anon memang tanpa nama)
--   - REGISTERED (email ada) → 'Pengguna' + 6 hex  (jelas belum pilih nama,
--                              TIDAK menyamar sebagai 'Anon')
--   `needs_onboarding` tetap true untuk keduanya → gerbang root memaksa
--   memilih nama sebelum masuk app.
--
--   Kolom nickname wajib 3-20 char & unik → 'Pengguna'+6hex (14 char) aman,
--   pola unik per-user (dari id) + retry suffix bila bentrok.
--
-- CARA APPLY: Management API (1 statement create fn).
-- ============================================================

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_nick text;
  v_try int := 0;
  v_hex text := upper(substr(replace(new.id::text, '-', ''), 1, 8));
  v_registered boolean := coalesce(new.email, '') <> '';
begin
  loop
    v_try := v_try + 1;
    -- Registered → 'Pengguna' + 6 hex (jelas belum pilih nama, bukan 'Anon').
    -- Anon       → 'Anon' + 8 hex (tetap).
    if v_registered then
      v_nick := 'Pengguna' || substr(v_hex, 1, 6);
    else
      v_nick := 'Anon' || v_hex;
    end if;
    if v_try > 1 then
      v_nick := v_nick || v_try::text;
    end if;

    begin
      insert into public.profiles
        (id, nickname, is_registered, status, created_at, last_seen,
         needs_onboarding)
      values (
        new.id,
        v_nick,
        v_registered,
        'offline',
        coalesce(new.created_at, now()),
        coalesce(new.created_at, now()),
        true
      )
      on conflict (id) do nothing;
      return new;                       -- sukses
    exception when unique_violation then
      if v_try >= 5 then
        return new;                     -- menyerah; purge_ghost_users jaring
      end if;
    end;
  end loop;
exception when others then
  -- JANGAN menggagalkan pembuatan user hanya karena profil gagal dibuat.
  return new;
end;
$function$;

-- Verifikasi setelah apply:
--   -- user registered baru harus ber-nickname 'PenggunaXXXXXX' (bukan Anon):
--   select nickname from public.profiles
--    where is_registered = true and needs_onboarding = true
--    order by created_at desc limit 5;
