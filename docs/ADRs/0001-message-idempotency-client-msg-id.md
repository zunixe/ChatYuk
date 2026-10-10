# ADR-0001: Idempotency message creation (`client_msg_id`) — catat & tunda

- Status: **Diterima (catat-tunda)** — 2026-10-10
- Konteks: audit read-only menemukan message creation tidak idempoten server-side.
- Keputusan: **tidak migrasi sekarang**; catat risiko + cara ukur; contoh idempoten
  yang benar (`email_worker_claim`, `credit_welcome_bonus`, `credit_play_topup`)
  jadi acuan saat dibutuhkan.

## Konteks (terverifikasi)

- Insert pesan langsung dengan RLS `auth.uid() == sender_id`, tanpa
  `client_msg_id`/key (`supabase/schema_part2.sql`, `20260905150000_anon_gate.sql`).
- `pendingId = pending-<microseconds>` hanya lokal, tidak dikirim ke server.
- Dedupe hanya client: `chat_stream_session.dart` skip by `id`, `loadOlder`
  seen-set, outbox `enqueue` replace by `pendingId` + `remove` pasca sukses.
- Poin dijamin via `deduct/refund`, bukan via pesan.

## Masalah

Retry saat jaringan putus-nyambung (timeout lalu kirim ulang) bisa menyimpan
**2 baris** untuk 1 pesan user. Jarang + sebagian tertutup dedupe client, tapi
tidak tertutup penuh (dua device / reinstall / race retry).

## Opsi dipertimbangkan

1. **Tambah `client_msg_id` UUID + UNIQUE per sender + `ON CONFLICT DO NOTHING`**
   - Pro: retry aman penuh, standar industri.
   - Kontra: migrasi kolom + backfill + ubah kontrak insert + risiko konflik
     dengan 454 migrasi lain; perlu koordinasi client lama (backward compat).
2. **Biarkan (status quo)** — andalkan dedupe client + outbox.
   - Pro: 0 risiko migrasi.
   - Kontra: celah ganda tetap ada.
3. **Dedupe window server** (tolak insert identik `sender+text+created_at` dalam
   N detik tanpa skema baru).
   - Pro: tanpa kolom baru. Kontra: heuristik, false-positive mungkin.

## Keputusan

Pilih **opsi 2 sekarang** (tunda), dengan opsi 1 sebagai arah saat bukti
duplikat muncul di produksi. Alasan: frekuensi rendah, biaya migrasi > manfaat
saat ini, sesuai change policy (simplest architecture).

## Cara mengukur (saat dibutuhkan)

- Query duplikat: grup `sender_id, text, date_trunc('minute', created_at)`
  dengan count > 1 di `private_messages`.
- Ambang: bila duplikat > 0,1% pesan/hari → aktifkan opsi 1.

## Konsekuensi

- Tidak ada perubahan kode/skema dari ADR ini.
- Saat opsi 1 dieksekusi: migrasi tambah kolom + kontrak API + test idempotency
  (kirim 2x `client_msg_id` sama → 1 baris) + catat di `MIGRATION_LOG.md`.
