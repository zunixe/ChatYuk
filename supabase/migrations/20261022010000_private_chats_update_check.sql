-- Pengerasan policy UPDATE private_chats dengan WITH CHECK.
--
-- Sebelumnya policy hanya punya USING (auth.uid() = ANY(participants)), tanpa
-- WITH CHECK. Akibatnya setelah UPDATE, baris bisa berisi participants yang
-- TIDAK lagi memuat pemanggil (mis. ia mengeluarkan dirinya sendiri).
--
-- WITH CHECKmenilai nilai BARU: pemanggil WAJIB tetap menjadi peserta.
-- Perubahan participants sendiri tetap ditahan trigger
-- check_private_chat_update ('Cannot modify participants'), jadi dua lapis.
--
-- SAFE: mengganti policy `private_chats_update` (tabel bersama) —
--      named: private_chats. Dampak fitur: hanya pin/mute/hide/read-receipt
--       (semua tetap memakai participants sendiri).
drop policy if exists private_chats_update on public.private_chats;
create policy private_chats_update
  on public.private_chats
  for update
  using (auth.uid() = ANY (participants))
  with check (auth.uid() = ANY (participants));
