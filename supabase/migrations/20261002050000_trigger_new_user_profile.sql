-- ============================================================
-- TRIGGER: auto-buat baris `profiles` saat `auth.users` dibuat.
--
-- LATAR (insiden 2026-10-02, docs/INCIDENT_STALE_CLEANUP_MASS_DELETE.md):
--   1646 dari 1671 arsip `stale_cleanup` adalah "user hantu":
--   `auth.users` ada, `profiles` TIDAK PERNAH dibuat (nickname '',
--   created_at NULL, last_seen_at NULL, tanpa device).
--
--   Penyebab: tidak ada trigger di `auth.users` (diverifikasi kosong).
--   Profil hanya dibuat `AuthService.registerProfile()` dari layar register.
--   `AuthProvider._init` memanggil `signInAnonymously()` lalu `getProfile()`;
--   bila profil tidak ada, profil TIDAK dibuat. Setiap sesi anon yang tidak
--   dilanjutkan (user tutup app, hanya lihat-lihat, crash) → 1 baris hantu.
--
--   Terukur: 6 hantu baru dalam ~10 jam pada 30 Sep. Ini akar masalahnya.
--
-- SOLUSI (opsi A — user memilih): trigger `AFTER INSERT ON auth.users`
-- yang membuat baris `profiles` minimal. Semua kolom NOT NULL di `profiles`
-- sudah punya DEFAULT, KECUALI nickname yang punya UNIQUE constraint —
-- jadi nickname WAJIB digenerate unik di sini.
--
-- ⚠️ JEBAKAN YANG DITEMUKAN SAAT UJI (penting):
--   Percobaan pertama memakai nickname default `'Anon'` dan GAGAL diam-diam:
--   `profiles_nickname_unique` (UNIQUE (nickname)) menolak baris kedua
--   dst. → 'duplicate key value violates unique constraint
--   "profiles_nickname_unique"'. Karena fungsi trigger menelan error
--   (`exception when others then null`), kegagalan itu TAK TERLIHAT dan
--   hantu TETAP terbentuk — trigger seolah jalan padahal tidak.
--   Terbukti: user uji setelah trigger terpasang masih punya profil NULL.
--   → nickname harus UNIK PER USER.
--
-- PERTIMBANGAN YANG SUDAH DIVERIFIKASI:
--   - `profiles` NOT NULL: seluruhnya ber-DEFAULT kecuali nickname →
--     insert minimal cukup `id` + `nickname` + `is_registered`.
--   - `profiles_nickname_unique` = UNIQUE (nickname) → generate dari
--     potongan UUID (32^8 kombinasi) + retry bila bentrok.
--   - RLS `profiles_insert_own` butuh `auth.uid() = id` + `_anon_write_ok()`,
--     sedangkan di dalam trigger auth.uid() belum tentu user baru →
--     fungsi trigger SECURITY DEFINER (owner `postgres` punya BYPASSRLS,
--     RLS tidak forced) sehingga lolos, sama polanya dengan
--     `delete_my_account`/`admin_delete_anon_user`.
--   - Idempoten: `on conflict (id) do nothing` — kalau `registerProfile`
--     sudah membuat barisnya, trigger tidak menimpa.
--   - `is_registered` = true bila email ada.
--
-- DAMPAK: setiap sesi anon kini langsung punya baris profil (nickname
--   "AnonXXXXXX" sampai user memilih sendiri). Kelas hantu hilang.
--   `purge_ghost_users` tetap ada sebagai jaring pengaman.
--
-- Tidak FROZEN. CARA APPLY: Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_nick text;
  v_try int := 0;
begin
  -- Nickname unik: "Anon" + 6 hex pertama dari UUID (dengan retry bila
  -- kebetulan bentrok). Tidak memakai DEFAULT 'Anon' karena UNIQUE.
  loop
    v_try := v_try + 1;
    v_nick := 'Anon' || upper(
      substr(replace(new.id::text, '-', ''), 1, 6)
    );
    if v_try > 1 then
      -- Retry: tambahkan entropi dari jam (jarang terjadi).
      v_nick := v_nick || v_try::text;
    end if;

    begin
      insert into public.profiles
        (id, nickname, is_registered, status, created_at, last_seen)
      values (
        new.id,
        v_nick,
        coalesce(new.email, '') <> '',
        'offline',
        coalesce(new.created_at, now()),
        coalesce(new.created_at, now())
      )
      on conflict (id) do nothing;
      return new;                       -- sukses
    exception when unique_violation then
      if v_try >= 5 then
        return new;                     -- menyerah; purge_ghost_users jaring
      end if;
      -- coba lagi dengan entropi tambahan
    end;
  end loop;
exception when others then
  -- JANGAN menggagalkan pembuatan user hanya karena profil gagal dibuat
  -- (mis. race dengan registerProfile). Hantu tersisa ditangani
  -- `purge_ghost_users`, bukan dengan menggagalkan registrasi user.
  return new;
end;
$fn$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user_profile();

revoke execute on function public.handle_new_user_profile()
  from public, anon, authenticated;

-- Verifikasi setelah apply:
--   1) Trigger terpasang:
--      select tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid
--       where c.relname='users' and not t.tgisinternal;
--   2) Uji fungsional — hantu baru harus 0 setelah ini:
--      select count(*) from auth.users u
--        left join public.profiles p on p.id=u.id
--       where u.is_anonymous and u.email is null and p.id is null
--         and u.created_at > now();   -- user anon baru sesudah trigger
--   3) Profil terisi:
--      select id, nickname, is_registered, status from public.profiles
--       order by created_at desc limit 5;
