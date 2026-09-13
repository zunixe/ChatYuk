-- ============================================================
-- Toggle admin: anon + dummy boleh call
--
-- Permintaan owner: pengaturan global di panel admin untuk mengaktifkan
-- call bagi anon & dummy. ON = anon/dummy bisa menelepon; OFF = hanya
-- user terdaftar (+ admin) seperti sebelumnya.
--
-- Alasan default OFF: anon/dummy bisa bikin akun baru tiap di-block →
-- spam call/push murah (griefing). Toggle memberi kontrol ke admin.
-- ============================================================

alter table public.app_settings
  add column if not exists call_anon_enabled boolean not null default false;

drop policy if exists calls_insert on public.calls;
create policy calls_insert on public.calls
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
