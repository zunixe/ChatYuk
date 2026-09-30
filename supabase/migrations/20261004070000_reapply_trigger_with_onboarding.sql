-- ============================================================
-- RE-APPLY trigger pencegah hantu + flag needs_onboarding (Opsi B).
--
-- LATAR: trigger `handle_new_user_profile` (20261004030000) mencegah hantu
--   tapi bikin user anon langsung masuk (profil otomatis dianggap lengkap).
--   Rollback di 20261004040000. Kini dipasang ULANG dengan kolom penanda
--   `needs_onboarding = true` (dibuat 20261004060000) supaya gate tahu
--   profil ini BELUM disetup user → tetap diarahkan ke layar isi nickname.
--
-- Perbedaan dari 20261004030000: kolom insert menyertakan `needs_onboarding`
--   = true. Sisa logika identik (nickname unik, retry, idempoten, tahan
--   error, SECURITY DEFINER).
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
    v_nick := 'Anon' || upper(substr(replace(new.id::text, '-', ''), 1, 8));
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
        coalesce(new.email, '') <> '',
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
--       where c.relname='users' and not t.tgisinternal;   -- on_auth_user_created
--   2) Uji: user anon baru → profil ada + needs_onboarding=true.
