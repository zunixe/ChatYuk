-- Restore policy calls_insert dengan cabang call_anon_enabled (toggle admin).
--
-- INSIDEN: 20260912090000_call_anon_toggle.sql TERCATAT di schema_migrations
-- tapi policy live ternyata masih versi 20260912000050 (registered-only
-- absolut, TANPA cabang `call_anon_enabled`). Jadi anon/dummy tetap ditolak
-- walau app_settings.call_anon_enabled = true → "Hanya akun terdaftar yang
-- bisa melakukan panggilan".
--
-- Penyebab pola klasik (lihat APPLIED_VIA_API.md): migrasi ditandai applied
-- tapi SQL-nya tidak pernah benar-benar dieksekusi / tertimpa re-apply versi
-- lama. Solusi: re-apply definisi policy versi BENAR (idempoten).
--
-- Isi identik dengan 20260912090000_call_anon_toggle.sql (sumber kebenaran).
--
-- SAFE: policy calls_insert di tabel bersama `calls` — hanya menambah cabang
-- izin (anon+dummy saat toggle ON); tidak menghapus izin registered/admin.
-- Fitur terdampak: panggilan audio/video 1:1 (call). Tidak mengubah
-- calls_select/RLS lain. Verifikasi setelah apply: simulasi role
-- authenticated untuk dummy & anon dengan call_anon_enabled=true harus lolos.
drop policy if exists calls_insert on public.calls; -- SAFE: restore policy calls_insert (tabel bersama `calls`) ke definisi benar 20260912090000; hanya menambah cabang izin anon/dummy saat toggle ON, tidak mencabut izin registered/admin. Fitur: panggilan audio/video 1:1.
create policy calls_insert on public.calls -- SAFE: idem — re-apply definisi 20260912090000 yang tercatat applied tapi tertimpa versi lama; menambah cabang call_anon_enabled.
  for insert to authenticated
  with check (
    auth.uid() = caller_id
    and (
      -- Admin selalu boleh.
      coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
      -- User terdaftar (bukan sesi dummy) selalu boleh.
      or (
        coalesce((select is_registered from public.profiles where id = auth.uid()), false)
        and not exists (
          select 1 from public.admin_dummy_uids() du where du = auth.uid()
        )
      )
      -- Anon & dummy: hanya bila toggle admin ON.
      or (
        coalesce((select call_anon_enabled from public.app_settings where id = 'global'), false)
        and (
          auth.uid() in (select du from public.admin_dummy_uids() du)
          or coalesce((select is_registered from public.profiles where id = auth.uid()), false) = false
        )
      )
    )
  );
