-- ============================================================
-- PASANG trigger pencegah "user hantu" — AKAR insiden mass-delete.
--
-- LATAR: insiden 2026-10-02 (docs/INCIDENT_STALE_CLEANUP_MASS_DELETE.md):
--   1679 user dihapus massal (reason=stale_cleanup). 1646 di antaranya
--   "user hantu": ada di `auth.users` (dibuat `signInAnonymously`) tapi
--   TIDAK PERNAH punya baris `profiles` (profil hanya dibuat lewat
--   registerProfile yang bisa tidak dijalankan: user tutup app / lihat-lihat
--   / crash). Hantu menumpuk → dibersihkan massal.
--
--   Migration `20261002050000_trigger_new_user_profile.sql` SUDAH ditulis
--   di repo tapi TIDAK PERNAH ter-apply ke produksi (verifikasi 2026-10-04:
--   `pg_trigger` auth.users KOSONG, `handle_new_user_profile` TIDAK ADA).
--   Akibatnya hantu MASIH terbentuk (15 hantu terbaru 30 Sep 16:16).
--
-- SOLUSI: trigger `AFTER INSERT ON auth.users` → buat baris `profiles`
--   minimal. Setiap user anon langsung punya profil → kelas hantu hilang.
--
-- Penyesuaian PENTING vs versi 20261002050000:
--   - Unique index baru `profiles_nickname_lower_unique`
--     (lower(trim(nickname))) — generate nickname lebih panjang & cek
--     bentrok pakai lower(), bukan sekadar nickname.
--   - Idempoten (`on conflict (id) do nothing`) — registerProfile boleh
--     menimpa bila user memilih nama sendiri.
--   - SECURITY DEFINER (owner punya BYPASSRLS) → lolos RLS insert.
--   - Menelan error → JANGAN gagalkan pembuatan user (jaring
--     `purge_ghost_users` tetap ada).
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
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
  loop
    v_try := v_try + 1;
    -- "Anon" + 8 hex dari UUID (entropi lebih besar dari versi lama 6 hex,
    -- mengurangi bentrok dengan index lower(nickname) yang case-insensitive).
    v_nick := 'Anon' || upper(substr(replace(new.id::text, '-', ''), 1, 8));
    if v_try > 1 then
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
  -- JANGAN menggagalkan pembuatan user hanya karena profil gagal dibuat.
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
--   2) Uji: buat user anon baru → profil harus langsung ada (hantu=0).
