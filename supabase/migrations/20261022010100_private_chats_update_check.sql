-- Pengerasan policy UPDATE private_chats dengan WITH CHECK.
--
-- Sebelumnya policy hanya punya USING (auth.uid() = ANY(participants)), tanpa
-- WITH CHECK. Akibatnya setelah UPDATE, baris bisa berisi participants yang
-- TIDAK lagi memuat pemanggil (mis. ia mengeluarkan dirinya sendiri).
--
-- WITH CHECK menilai nilai BARU: pemanggil WAJIB tetap menjadi peserta.
-- Perubahan participants sendiri tetap ditahan trigger
-- check_private_chat_update ('Cannot modify participants'), jadi dua lapis.
--
-- SAFE: mengganti policy `private_chats_update` (tabel bersama) —
--      named: private_chats. Dampak fitur: hanya pin/mute/hide/read-receipt
--       (semua tetap memakai participants sendiri).
-- SAFE: ganti isi policy (bukan cabut akses) — hanya menambah WITH CHECK.
drop policy if exists private_chats_update on public.private_chats; -- SAFE: drop policy lama hanya untuk diganti versi +WITH CHECK (tidak mencabut fitur).
-- Policy diganti untuk MENAMBAH WITH CHECK; aturan sama dgn USING (peserta
-- sendiri) → tidak melonggarkan akses. Fitur terdampak: pin/mute/hide/
-- read-receipt private chat (tetap jalan).
create policy private_chats_update -- SAFE: WITH CHECK = aturan USING (peserta sendiri); fitur pin/mute/hide/read-receipt tetap jalan.
  on public.private_chats
  for update
  using (auth.uid() = ANY (participants))
  with check (auth.uid() = ANY (participants));
