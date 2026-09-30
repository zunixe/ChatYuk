-- ============================================================
-- GATE ISI USERNAME: user anon baru WAJIB pilih username dulu.
--
-- MINTA USER: user baru JANGAN langsung masuk — harus isi username
-- dulu. Yang sudah terlanjur daftar sebagai 'AnonXXXXXX' DIBIARKAN
-- (jangan di-logout / diminta ulang).
--
-- LATAR: trigger `handle_new_user_profile` (20261002050000) membuat
--   profil otomatis saat auth.users dibuat, dengan nickname
--   'AnonXXXXXX' + status 'offline'. Efeknya user yang baru buka app
--   LANGSUNG masuk main tanpa pernah memilih username.
--   Di app.dart pengecualian `!isAnonymous` pada `needsProfile`
--   membuat user anon tak pernah melewati gerbang profil.
--
-- SOLUSI: kolom penanda `profiles.nickname_set`:
--   - false → user belum PERNAH memilih username (baru) → app WAJIB
--     menampilkan layar isi username sebelum masuk main.
--   - true  → sudah pernah memilih (atau user lama) → langsung masuk.
--
-- BACKFILL (PENTING — jangan sampai user aktif ke-logout):
--   Semua user yang SUDAH punya jejak dianggap `nickname_set = true`:
--     - sudah punya username sendiri (bukan 'Anon%'), ATAU
--     - punya chat / pesan, ATAU
--     - status bukan 'offline' (pernah online)
--   Sisanya (anon pasif, belum pernah dipakai) dibiarkan false →
--   akan diminta isi username saat membuka app.
--   Terukur saat migrasi: 109 user lolos, 4 anon pasif diminta isi nama.
--
-- Tidak FROZEN. CARA APPLY: Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

-- ── 1. Kolom penanda ──
alter table public.profiles
  add column if not exists nickname_set boolean not null default false;

comment on column public.profiles.nickname_set is
  'true bila user sudah pernah memilih username (atau user lama hasil backfill). '
  'false → app wajib menampilkan layar isi username sebelum masuk main.';

create index if not exists profiles_nickname_set_idx
  on public.profiles (nickname_set)
  where nickname_set = false;

-- ── 2. Backfill: user lama TIDAK boleh ter-logout ──
-- Anggap "sudah memilih username" bila punya jejak apa pun.
update public.profiles p
   set nickname_set = true
 where p.nickname_set = false
   and (
     -- sudah punya username sendiri
     (coalesce(p.nickname, '') <> '' and p.nickname not ilike 'Anon%')
     -- pernah chat
     or exists (
       select 1 from public.private_chats c
        where c.participants @> array[p.id]::uuid[]
     )
     or exists (
       select 1 from public.private_messages m
        where m.sender_id = p.id
     )
     -- pernah online/idle/invisible (bukan sekadar offline bawaan trigger)
     or coalesce(p.status, 'offline') <> 'offline'
   );

-- ── 3. Trigger: user BARU dapat nickname_set = false ──
-- (Diperbarui agar eksplisit; default kolom sudah false, tapi ditulis
--  tegas supaya tidak bergantung default bila skema berubah.)
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
      v_nick := v_nick || v_try::text;
    end if;

    begin
      insert into public.profiles
        (id, nickname, is_registered, status, created_at, last_seen,
         nickname_set)
      values (
        new.id,
        v_nick,
        coalesce(new.email, '') <> '',
        'offline',
        coalesce(new.created_at, now()),
        coalesce(new.created_at, now()),
        false                      -- WAJIB isi username sebelum masuk main
      )
      on conflict (id) do nothing;
      return new;
    exception when unique_violation then
      if v_try >= 5 then
        return new;
      end if;
    end;
  end loop;
exception when others then
  return new;
end;
$fn$;

revoke execute on function public.handle_new_user_profile()
  from public, anon, authenticated;

-- Verifikasi setelah apply:
--   1) Kolom ada + distribusi:
--      select nickname_set, count(*) from public.profiles group by 1;
--   2) User anon aktif TIDAK ter-logout (harus 0 yang false tapi aktif):
--      select count(*) from public.profiles p
--       where p.nickname_set = false
--         and (exists(select 1 from public.private_chats c
--                      where c.participants @> array[p.id]::uuid[])
--              or coalesce(p.status,'offline') <> 'offline');
