-- Panggilan hanya untuk user TERDAFTAR (absolute, bukan toggle).
--
-- Sebelumnya RLS calls_insert hanya cek auth.uid() = caller_id — session
-- ANONIM juga punya auth.uid(), jadi anon bisa membuat panggilan ke user
-- mana pun (spam push via trigger notify_call_ringing → griefing murah:
-- akun baru tiap kali di-block).
--
-- Guard: registered-only ABSOLUTE + bypass dummy & admin (pola sama
-- dengan create_private_room / send_coins / send_gift).
-- call_push TIDAK diubah — dipanggil trigger dengan caller dari row
-- (sudah tervalidasi oleh RLS insert ini).

drop policy if exists calls_insert on public.calls;
create policy calls_insert on public.calls
  for insert to authenticated
  with check (
    auth.uid() = caller_id
    and (
      coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
      or auth.uid() in (select du from public.admin_dummy_uids() du)
      or coalesce(
        (select is_registered from public.profiles where id = auth.uid()),
        false)
    )
  );
