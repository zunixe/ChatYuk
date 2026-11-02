# Matriks Uji Ekonomi YukCoin — End to End

Dokumen ini adalah daftar uji wajib untuk setiap perubahan yang menyentuh
ekonomi YukCoin (harga, debit/kredit, misi, withdraw, flag global). Ekonomi
= uang nyata → uji harus detail, bukan "coba sekilas".

Tiga lapis pertahanan:

| Lapis | Alat | Kapan |
|---|---|---|
| 1. SQL transaksional | `bash scripts/run_sql_tests.sh` (semua file `supabase/tests/`) | setiap perubahan RPC/migrasi |
| 2. Matriks flag E2E | `bash scripts/test_economy_toggle.sh` | setelah ubah perilaku `points_enabled` |
| 3. HP (manual) | matriks di bawah | sebelum rilis / setelah migrasi ekonomi |

Akun yang dipakai: **hanya akun dummy** (`dummy_accounts`) — aturan repo
melarang menyentuh akun asli untuk uji.

---

## A. Matriks HP — perilaku normal (points_enabled ON)

Untuk setiap baris: catat **saldo sebelum**, lakukan aksi, catat **saldo
sesudah** + **UI yang tampil**, lalu verifikasi ledger via SQL
(kueri verifikasi di bagian C).

| # | Aksi | Akun | UI yang diharapkan | Saldo | Ledger |
|---|------|------|--------------------|-------|--------|
| A1 | Klik Match, saldo 0 | male | Dialog "YukCoin tidak cukup" + CTA top-up; TIDAK masuk antrean | tetap 0 | 0 baris |
| A2 | Klik Match, saldo ≥2, antre lalu **Cancel** sebelum dapat match | male | Fase searching → batal | **utuh** (fee bukan saat klik) | 0 baris `match_search` |
| A3 | Klik Match → ketemu lawan | male | Masuk panggilan | **−2 tepat sekali** | 1 baris `match_search` −2 + `platform_revenue` +2 |
| A4 | Klik Match → ketemu lawan | female | Masuk panggilan, tanpa dialog koin | utuh (female gratis) | 0 baris; male partner −2 |
| A5 | Next → ketemu lawan baru | male | Panggilan baru | −2 lagi (1× per pair) | baris `match_search` baru |
| A6 | Join room biasa | siapa pun, saldo 0 | Masuk room (GRATIS) — tidak ada dialog harga | utuh | 0 baris |
| A7 | Buat room private | male | Debit biaya room | −`room_create_cost` | `room_create` |
| A8 | Filter gender di Online | siapa pun, saldo 0 | Filter tersimpan — TIDAK ada charge/dialog koin | utuh | 0 baris |
| A9 | Pencarian Nearby | siapa pun, saldo 0 | Hasil tampil — TIDAK ada charge | utuh | 0 baris |
| A10 | Voice call 2 menit | male | Billing per menit | −`call_audio_cost_per_min`×2 | `call_audio` ×2 |
| A11 | Video call 2 menit | male → female | Billing per menit; **female dapat income** | male −`call_video_cost_per_min`×2; female +net | `call_video` debit + `call_video_income` credit |
| A12 | Kirim gift | siapa pun | Toast sukses | −harga gift; penerima +net | `gift_sent`/`gift_recv` + `platform_revenue` cut |
| A13 | Kirim gambar di chat | male | Terkirim | −`cost_chat_image` | `chat_image` |
| A14 | Kirim teks biasa | siapa pun | Terkirim — gratis | utuh | 0 baris |
| A15 | View-once dibuka | male | Foto terbuka | −`cost_view_once` | `view_once` |
| A16 | Undo / edit pesan | siapa pun | Jalan — GRATIS, tanpa dialog koin | utuh | 0 baris |
| A17 | Klaim misi harian | siapa pun | Toast reward | +reward | `mission_reward` — bucket by-gender: female → `earned`, selain female → `bonus` (2026-11-01) |
| A18 | Withdraw di bawah minimum | female | Error batas minimum | utuh | 0 baris |
| A19 | Withdraw valid | female | Request pending, saldo **langsung terdebit** | −jumlah | `withdraw` −N |
| A20 | Withdraw ditolak admin | female | Status rejected | **refund penuh** | `withdraw_refund` +N |
| A21 | Koin habis di tengah call | male | Jeda + dialog top-up (male) | — | — |
| A22 | Free-limit harian habis | female | Dialog "Batas gratis habis" (BUKAN top-up) | — | — |
| A23 | Slot foto ke-4 dst | siapa pun | Upload jalan — gratis, label "Gratis" | utuh | 0 baris |
| A24 | History YukCoin | siapa pun | Transaksi call/gift/match/topup/mission/withdraw tampil berlabel (bukan "Lainnya") | — | — |
| A25 | **Lawan menutup call** di match | male | Teks **"{nama} keluar"** di layar + subtitle + caption bawah; tombol mic/kamera/end hilang; **BUKAN spinner** | utuh | 0 baris baru |
| A26 | Next setelah lawan keluar | male | Langsung masuk antrean; match baru → −2 lagi | −2 per pair baru | `match_search` baru |
| A27 | **Kamera sendiri (PiP)** di match — terutama Xiaomi/Redmi/MIUI | siapa pun | Tap Match → dialog izin kamera+mic OS muncul bila belum ada; PiP kamera lokal tampil (bukan kotak hitam); toggle kamera off/on & switch depan/belakang jalan. Bila izin ditolak → dialog izin (bukan match tanpa kamera); bila kamera mati total → pesan error media, BUKAN "{nama} keluar" | — | — |

## B. Matriks flag `points_enabled = false`

Jalankan `bash scripts/test_economy_toggle.sh` — hasil harus 7/7.
Untuk uji HP manual saat OFF (perlu maintenance window singkat):

| # | Aksi | Hasil yang diharapkan |
|---|------|------------------------|
| B1 | Match / call / gambar / view-once / buat room | **Gratis** — jalan tanpa debit |
| B2 | Kirim gift / kirim koin / subscribe | **Ditolak** "Points system disabled" |
| B3 | Klaim misi / welcome bonus | Tidak mengkredit (`POINTS_DISABLED` / `granted:false`) |
| B4 | Withdraw | Ditolak `POINTS_DISABLED` |
| B5 | Setelah flag ON lagi | Semua fitur berbayar menagih normal |

> Catatan: `test_economy_toggle.sh` melakukan seluruh matriks dalam satu
> transaksi — flag tidak pernah tertinggal OFF, dan tidak ada baris uji
> yang tersisa di ledger.

## C. SQL verifikasi cepat

```sql
-- ledger user dalam 1 jam terakhir
select bucket, type, amount, ref_id, created_at
from coin_ledger where user_id = '<uid>'
order by created_at desc limit 20;

-- rekonsiliasi global (harus 0 baris selain temuan orphan yang diketahui)
select * from public.economy_invariant_check(100);

-- revenue hari ini
select source, sum(amount) from platform_revenue
where created_at > now() - interval '1 day' group by 1;
```

## D. Release gate — wajib hijau sebelum kirim build

- [ ] `bash scripts/run_sql_tests.sh` → semua file lulus
      (`economy_invariants` 14, `economy_matrix` 33, `economy_money` 32,
      `random_match` 20, dsb)
- [ ] `bash scripts/test_economy_toggle.sh` → 7/7 + flag akhir true
- [ ] `flutter test` → 100% hijau (termasuk `strings_vocabulary_test`)
- [ ] `bash scripts/check_migrations.sh --all` → OK bersih
- [ ] `select * from public.economy_invariant_check(100)` → **0 baris**
      (3 orphan lama tercatat di `economy_audit_exclusions`; temuan baru
      tetap muncul sebagai pelanggaran)
- [ ] Matriks HP A1–A27 diverifikasi minimal untuk fitur yang diubah
- [ ] `flutter analyze` → 0 error/warning di file yang diubah
