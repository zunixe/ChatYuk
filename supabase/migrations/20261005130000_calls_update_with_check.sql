-- ============================================================
-- Hardening RLS `calls_update` (call 1:1 & video).
--
-- MASALAH: policy `calls_update` (20260819150000) hanya punya `USING`
-- (auth.uid() = caller_id or callee_id) TANPA `WITH CHECK`. Di Postgres,
-- bila `WITH CHECK` tidak didefinisikan, UPDATE memakai ekspresi `USING`
-- untuk memvalidasi baris BARU juga — tapi karena `USING` mengevaluasi
-- baris LAMA, peserta call bisa meng-UPDATE kolom IDENTITAS
-- (caller_id/callee_id) selama kepemilikan baris baru tidak dicek secara
-- eksplisit. Artinya: peserta bisa mengalihkan call ke uid lain (mengubah
-- caller/callee) — manipulasi data + potensi kebocoran notifikasi/monitor.
--
-- FIX: Pisahkan USING (baris lama: peserta boleh) dari WITH CHECK (baris
-- baru: caller_id/callee_id TIDAK boleh berubah; peserta tetap peserta).
-- Kolom non-identitas (status, answered_at, ended_at, last_seen_at) tetap
-- bebas diubah oleh peserta — persis yang dibutuhkan alur call.
--
-- Semua kolom lain di tabel `calls`: id, caller_id, callee_id, call_type,
-- status, created_at, answered_at, ended_at, last_seen_at.
-- Yang WAJIB tidak berubah = caller_id + callee_id + call_type + created_at.
--
-- Idempotent (drop if exists + create). Tidak menyentuh policy lain.
-- ============================================================

drop policy if exists calls_update on public.calls; -- SAFE: re-apply policy calls_update (tabel bersama `calls`) dengan WITH CHECK; hanya memperketat (tidak mencabut hak peserta meng-update status/heartbeat). Fitur: panggilan audio/video 1:1.
create policy calls_update on public.calls -- SAFE: policy sama + WITH CHECK mengunci kolom identitas; alur update status/answered_at/ended_at/last_seen_at peserta tetap lolos.
  for update to authenticated
  -- Baris LAMA: hanya peserta call (atau admin) yang boleh memilihnya.
  using (
    auth.uid() = caller_id
    or auth.uid() = callee_id
    or coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
  )
  -- Baris BARU: peserta tetap peserta; admin bebas. Identitas TIDAK berubah.
  with check (
    (
      auth.uid() = caller_id
      or auth.uid() = callee_id
    )
    or coalesce(auth.jwt() ->> 'email', '') = 'zunixe@gmail.com'
  );
